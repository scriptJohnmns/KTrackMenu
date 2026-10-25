// =============================================================================
// main.cpp — ponto de entrada do programa
//
// Aqui o app é montado: lê os argumentos da linha de comando, garante que só
// exista uma cópia rodando, cria os três objetos C++ principais, entrega esses
// objetos para as telas em QML e coloca o ícone na bandeja do sistema.
//
// Visão geral dos arquivos:
//   configstore    → lê e grava o menu em ~/.config/trackpmenu/menu.json
//   menucontroller → atalho global, janela do menu radial e execução das ações
//   systembridge   → consultas ao sistema (apps instalados, atalhos do KDE…)
//   windowtracker  → janelas abertas e app em foco (via um script dentro do KWin)
//   qml/*.qml      → as telas (menu radial, configurações, editor de item)
// =============================================================================

#include <QCommandLineParser>
#include <QApplication>
#include <QIcon>
#include <QMenu>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QSystemTrayIcon>

#include <KDBusService>

#include "windowtracker.h"
#include "configstore.h"
#include "menucontroller.h"
#include "systembridge.h"
#include "togglestates.h"
#include "mediaplayers.h"

// Um "namespace" sem nome deixa o que está dentro visível só neste arquivo.
namespace
{
// O que o usuário pediu ao iniciar o programa.
enum class Mode { Settings, Daemon, Toggle, Quit };

// Converte os argumentos (ex.: "trackpmenu --toggle") em um Mode.
// Também cuida sozinho de --help e --version (imprime e encerra).
Mode parseMode(const QStringList &arguments)
{
    QCommandLineParser parser;
    parser.setApplicationDescription(QStringLiteral("Menu radial de atalhos para o TrackPoint"));
    parser.addHelpOption();
    parser.addVersionOption();
    const QCommandLineOption daemon(QStringLiteral("daemon"), QStringLiteral("Roda em segundo plano, sem abrir janela."));
    const QCommandLineOption toggle(QStringLiteral("toggle"), QStringLiteral("Mostra ou esconde o menu."));
    const QCommandLineOption quit(QStringLiteral("quit"), QStringLiteral("Encerra a instância em execução."));
    parser.addOptions({daemon, toggle, quit});
    parser.process(arguments);

    if (parser.isSet(quit))
        return Mode::Quit;
    if (parser.isSet(toggle))
        return Mode::Toggle;
    if (parser.isSet(daemon))
        return Mode::Daemon;
    // Sem argumentos: abre a janela de configurações.
    return Mode::Settings;
}
}

int main(int argc, char *argv[])
{
    // O objeto "aplicação" precisa existir antes de qualquer janela.
    // É QApplication, e não QGuiApplication, porque o seletor de ícones do KDE
    // é uma janela do tipo QWidget, e sem isso o programa travava (segfault).
    QApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("trackpmenu"));
    app.setApplicationDisplayName(QStringLiteral("TrackpMenu"));
    app.setOrganizationDomain(QStringLiteral("github.io"));
    app.setApplicationVersion(QStringLiteral(TRACKPMENU_VERSION)); // vem do CMakeLists.txt
    app.setDesktopFileName(QStringLiteral("io.github.trackpmenu"));
    app.setWindowIcon(QIcon::fromTheme(QStringLiteral("input-mouse")));
    // Por padrão o Qt encerra o app quando a última janela fecha. Aqui não:
    // o programa continua em segundo plano esperando o atalho.
    app.setQuitOnLastWindowClosed(false);

    // Usa o visual do KDE nos botões e campos, a não ser que o usuário tenha
    // escolhido outro estilo pela variável de ambiente.
    if (qEnvironmentVariableIsEmpty("QT_QUICK_CONTROLS_STYLE"))
        QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    // Lê os argumentos antes de se registrar no D-Bus, para que --help e
    // --version funcionem mesmo com outra cópia do app já aberta.
    const Mode initialMode = parseMode(app.arguments());

    // D-Bus é o "correio" que os programas do desktop usam para conversar entre si.
    // Com KDBusService::Unique, só uma cópia do app pode existir: se já houver uma
    // rodando, esta segunda cópia repassa seus argumentos para ela e encerra aqui.
    KDBusService service(KDBusService::Unique);

    // Os objetos principais. Eles vivem até o fim de main().
    ConfigStore config;
    SystemBridge system;
    ToggleStates toggles;
    WindowTracker windows;     // janelas abertas e app em foco (via KWin)
    MediaPlayers media;        // players de mídia abertos (via MPRIS)
    MenuController controller(&config, &toggles, &windows, &media);

    // O "engine" é quem carrega e executa os arquivos QML.
    // setContextProperty publica um objeto C++ para o QML com um nome: no QML,
    // "Config", "System", "Toggles", "Media" e "Controller" passam a ser esses objetos.
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("Config"), &config);
    engine.rootContext()->setContextProperty(QStringLiteral("System"), &system);
    engine.rootContext()->setContextProperty(QStringLiteral("Toggles"), &toggles);
    engine.rootContext()->setContextProperty(QStringLiteral("Media"), &media);
    engine.rootContext()->setContextProperty(QStringLiteral("Controller"), &controller);
    controller.setEngine(&engine);

    // ---- Ícone na bandeja do sistema (systray) ----
    // No Plasma ele aparece através do protocolo StatusNotifierItem.
    // Menu do clique direito:
    QMenu trayMenu;
    trayMenu.addAction(QIcon::fromTheme(QStringLiteral("view-app-grid")), QStringLiteral("Mostrar menu"), &controller, &MenuController::show);
    trayMenu.addAction(QIcon::fromTheme(QStringLiteral("configure")), QStringLiteral("Configurações…"), &controller, &MenuController::openSettings);
    trayMenu.addSeparator();
    trayMenu.addAction(QIcon::fromTheme(QStringLiteral("application-exit")), QStringLiteral("Sair"), &app, &QCoreApplication::quit);

    QSystemTrayIcon tray(app.windowIcon());
    tray.setToolTip(QStringLiteral("TrackpMenu"));
    tray.setContextMenu(&trayMenu);
    // connect(emissor, sinal, contexto, função): "quando o ícone for ativado,
    // rode esta função". Trigger = clique esquerdo, que abre as configurações.
    QObject::connect(&tray, &QSystemTrayIcon::activated, &controller, [&](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger)
            controller.openSettings();
    });
    tray.show();

    // Função "lambda" (uma função criada dentro de outra) que executa um Mode.
    // O [&] permite que ela use as variáveis locais de main(), como "controller".
    auto handle = [&](Mode mode) {
        switch (mode) {
        case Mode::Quit:
            QCoreApplication::quit();
            break;
        case Mode::Toggle:
            controller.toggle();
            break;
        case Mode::Settings:
            controller.openSettings();
            break;
        case Mode::Daemon:
            // Nada a fazer: só fica rodando em segundo plano.
            break;
        }
    };

    // Quando uma segunda cópia do app é aberta (ex.: "trackpmenu --toggle"), ela
    // manda seus argumentos para esta cópia por D-Bus, e eles chegam aqui.
    QObject::connect(&service, &KDBusService::activateRequested, &app, [&](const QStringList &arguments, const QString &) {
        handle(parseMode(arguments));
    });

    handle(initialMode);
    // Entra no "laço de eventos": espera cliques, teclas, mensagens D-Bus etc.
    // e só retorna quando o app é encerrado.
    return app.exec();
}
