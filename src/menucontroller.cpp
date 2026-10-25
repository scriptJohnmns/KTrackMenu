// =============================================================================
// menucontroller.cpp — implementação do MenuController (ver menucontroller.h)
//
// Fluxo de uso:
//   1. O usuário aperta o atalho → o KDE (KGlobalAccel) dispara m_action
//   2. m_action chama toggle() → show() → a janela Overlay.qml aparece
//   3. O usuário escolhe um item → o QML chama activate(item)
//   4. activate() fecha o menu e, um instante depois, execute() roda a ação
// =============================================================================

#include "menucontroller.h"

#include "windowtracker.h"
#include "configstore.h"
#include "togglestates.h"
#include "mediaplayers.h"

#include <QAction>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QGuiApplication>
#include <QIcon>
#include <QLocale>
#include <QProcess>
#include <QSettings>
#include <QStandardPaths>
#include <QQmlComponent>
#include <QQmlEngine>
#include <QQuickWindow>
#include <QTimer>
#include <QUrl>

#include <KGlobalAccel>
#include <KIO/ApplicationLauncherJob>
#include <KIO/OpenUrlJob>
#include <KWindowEffects>
#include <KService>
#include <LayerShellQt/Window>

namespace
{
// Atalhos padrão que abrem o menu:
//  - Launch(6): o código que o driver thinkpad_acpi manda no toque duplo do
//    TrackPoint (KEY_PROG4) em alguns ThinkPads. Fica no padrão por
//    compatibilidade; no T14 Gen 5 o firmware não manda nada.
//  - Favorites: a tecla de estrela dos ThinkPads (Fn+F12).
const QList<QKeySequence> defaultShortcuts{QKeySequence(Qt::Key_Launch6), QKeySequence(Qt::Key_Favorites)};

// Espera (em milissegundos) entre fechar o menu e executar a ação. Dá tempo ao
// compositor de tirar o menu da tela, para que capturas de tela e atalhos que
// dependem da janela em foco não "vejam" o menu.
constexpr int executeDelayMs = 120;

// Máximo de janelas no submenu "Janelas abertas": mais que isso fica difícil de mirar.
constexpr int maxWindows = 12;

// Marcos do contador de aberturas e o nome da "conquista" de cada um.
struct Achievement {
    int count;
    const char *title;
};
constexpr Achievement achievements[] = {
    {100, "Aprendiz do TrackPoint"},
    {1000, "Mestre do TrackPoint"},
    {10000, "Lenda do TrackPoint"},
};

// O contador fica num arquivo separado (~/.config/ktrackmenu/stats.ini), para
// não regravar o menu.json a cada abertura.
QSettings statsFile()
{
    return QSettings(QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/ktrackmenu/stats.ini"),
                     QSettings::IniFormat);
}

// Atalho para ler um campo de texto de um item, já sem espaços nas pontas.
// Ex.: str(item, "type") devolve "app", "command"...
QString str(const QVariantMap &item, const char *key)
{
    return item.value(QLatin1String(key)).toString().trimmed();
}
}

MenuController::MenuController(ConfigStore *config, ToggleStates *toggles, WindowTracker *windows, MediaPlayers *media, QObject *parent)
    : QObject(parent)
    , m_config(config)
    , m_toggles(toggles)
    , m_windows(windows)
    , m_media(media)
    , m_action(new QAction(this))
    , m_openCount(statsFile().value(QStringLiteral("openCount"), 0).toInt())
{
    // O KDE identifica o atalho pelo objectName da ação. O texto aparece em
    // Configurações do sistema → Atalhos.
    m_action->setObjectName(QStringLiteral("show-menu"));
    m_action->setText(QStringLiteral("Mostrar o menu do KTrackMenu"));
    // Registra o atalho global no KDE. Se o usuário já tinha escolhido outro
    // atalho antes, o KDE mantém a escolha dele (é o comportamento "autoloading").
    KGlobalAccel::self()->setDefaultShortcut(m_action, defaultShortcuts);
    KGlobalAccel::self()->setShortcut(m_action, defaultShortcuts);
    // A versão 0.1 só registrava a tecla do toque duplo. Quem nunca mexeu no
    // atalho ganha também a tecla de estrela. NoAutoloading = força a troca.
    if (KGlobalAccel::self()->shortcut(m_action) == QList<QKeySequence>{defaultShortcuts.first()})
        KGlobalAccel::self()->setShortcut(m_action, defaultShortcuts, KGlobalAccel::NoAutoloading);
    // O app se chamava TrackpMenu, e o KDE guardou o atalho com esse nome
    // ("trackpmenu"). Se ainda existir, apaga o registro antigo (liberando as
    // teclas) e passa o mesmo atalho para o KTrackMenu. Como o registro antigo
    // some, isto só acontece uma vez.
    const QList<QKeySequence> oldShortcut = KGlobalAccel::self()->globalShortcut(QStringLiteral("trackpmenu"), QStringLiteral("show-menu"));
    if (!oldShortcut.isEmpty()) {
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), QStringLiteral("/kglobalaccel"),
                                                  QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("unregister"));
        msg << QStringLiteral("trackpmenu") << QStringLiteral("show-menu");
        QDBusConnection::sessionBus().call(msg);
        KGlobalAccel::self()->setShortcut(m_action, oldShortcut, KGlobalAccel::NoAutoloading);
    }
    // Quando o atalho é apertado, a ação é "disparada" e chamamos toggle().
    connect(m_action, &QAction::triggered, this, &MenuController::toggle);
    // Se o atalho for trocado (por aqui ou nas Configurações do sistema),
    // avisa o QML para atualizar o texto exibido.
    connect(KGlobalAccel::self(), &KGlobalAccel::globalShortcutChanged, this, [this](QAction *action, const QKeySequence &) {
        if (action == m_action)
            Q_EMIT activationShortcutChanged();
    });
}

bool MenuController::isVisible() const
{
    return m_overlay && m_overlay->isVisible();
}

QKeySequence MenuController::activationShortcut() const
{
    // Uma ação pode ter vários atalhos; mostramos só o primeiro.
    const QList<QKeySequence> shortcuts = KGlobalAccel::self()->shortcut(m_action);
    return shortcuts.isEmpty() ? QKeySequence() : shortcuts.first();
}

void MenuController::setActivationShortcut(const QKeySequence &sequence)
{
    KGlobalAccel::self()->setShortcut(m_action, {sequence}, KGlobalAccel::NoAutoloading);
    Q_EMIT activationShortcutChanged();
}

void MenuController::resetActivationShortcut()
{
    KGlobalAccel::self()->setShortcut(m_action, defaultShortcuts, KGlobalAccel::NoAutoloading);
    Q_EMIT activationShortcutChanged();
}

void MenuController::toggle()
{
    if (isVisible())
        hide();
    else
        show();
}

QQuickWindow *MenuController::ensureOverlay()
{
    // Já criada (ou sem engine para criar): devolve o que houver.
    if (m_overlay || !m_engine)
        return m_overlay;

    // Cria a janela a partir do arquivo qml/Overlay.qml do módulo "KTrackMenu".
    QQmlComponent component(m_engine, "KTrackMenu", "Overlay");
    QObject *object = component.create();
    // qobject_cast converte com segurança: devolve nulo se não for uma janela.
    m_overlay = qobject_cast<QQuickWindow *>(object);
    if (!m_overlay) {
        qWarning() << "ktrackmenu: cannot create overlay" << component.errors();
        delete object;
        return nullptr;
    }

    if (QGuiApplication::platformName().startsWith(QLatin1String("wayland"))) {
        // No Wayland, uma janela comum não pode se posicionar sozinha nem ficar
        // por cima de tudo. O protocolo "layer-shell" resolve isso: a janela vira
        // uma camada do próprio desktop (como o painel do Plasma).
        // Precisa ser configurado ANTES de a janela aparecer pela primeira vez.
        auto *layer = LayerShellQt::Window::get(m_overlay);
        // Camada mais alta: acima de todas as janelas e painéis.
        layer->setLayer(LayerShellQt::Window::LayerOverlay);
        // Presa às quatro bordas = ocupa a tela inteira.
        layer->setAnchors(LayerShellQt::Window::Anchors(LayerShellQt::Window::AnchorTop | LayerShellQt::Window::AnchorBottom
                                                        | LayerShellQt::Window::AnchorLeft | LayerShellQt::Window::AnchorRight));
        // -1 = cobre também a área dos painéis em vez de desviar deles.
        layer->setExclusiveZone(-1);
        // Recebe todo o teclado enquanto estiver aberta (Esc, setas, 1–9…).
        layer->setKeyboardInteractivity(LayerShellQt::Window::KeyboardInteractivityExclusive);
        // Com vários monitores, abre no monitor em uso.
        layer->setWantsToBeOnActiveScreen(true);
        layer->setScope(QStringLiteral("ktrackmenu"));
    } else {
        // Sessão X11: uma janela sem bordas, sempre no topo e fora da barra de tarefas.
        m_overlay->setFlags(Qt::FramelessWindowHint | Qt::WindowStaysOnTopHint | Qt::Tool);
    }

    // Repassa o "mudei de visibilidade" da janela como o nosso visibleChanged.
    connect(m_overlay, &QWindow::visibleChanged, this, &MenuController::visibleChanged);
    return m_overlay;
}

void MenuController::show()
{
    QQuickWindow *overlay = ensureOverlay();
    if (!overlay)
        return;
    // Avisa o QML para voltar ao menu principal e esperar a posição do cursor.
    Q_EMIT showRequested();
    countOpen();
    if (QGuiApplication::platformName().startsWith(QLatin1String("wayland")))
        overlay->show(); // o layer-shell já faz a janela ocupar a tela toda
    else
        overlay->showFullScreen();
    // Pede o foco do teclado para a janela.
    overlay->requestActivate();
}

void MenuController::countOpen()
{
    QSettings stats = statsFile();
    m_openCount = stats.value(QStringLiteral("openCount"), 0).toInt() + 1;
    stats.setValue(QStringLiteral("openCount"), m_openCount);
    Q_EMIT openCountChanged();

    for (const Achievement &a : achievements) {
        if (a.count != m_openCount)
            continue;
        // Notificação do KDE, pelo padrão freedesktop (org.freedesktop.Notifications).
        // Argumentos do Notify: app, id a substituir (0 = nova), ícone, título,
        // texto, botões, dicas extras e tempo na tela (-1 = padrão do sistema).
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("/org/freedesktop/Notifications"),
                                                  QStringLiteral("org.freedesktop.Notifications"), QStringLiteral("Notify"));
        msg << QStringLiteral("KTrackMenu") << 0u << QStringLiteral("games-achievements") << QStringLiteral("🏆 %1").arg(QString::fromUtf8(a.title))
            << QStringLiteral("Você já abriu o menu %1 vezes!").arg(QLocale().toString(m_openCount)) << QStringList{} << QVariantMap{} << -1;
        QDBusConnection::sessionBus().send(msg);
    }
}

void MenuController::hide()
{
    if (m_overlay)
        m_overlay->hide();
}

void MenuController::openSettings()
{
    // Cria a janela de configurações só na primeira vez; depois reaproveita.
    if (!m_settings && m_engine) {
        QQmlComponent component(m_engine, "KTrackMenu", "Settings");
        QObject *object = component.create();
        m_settings = qobject_cast<QQuickWindow *>(object);
        if (!m_settings) {
            qWarning() << "ktrackmenu: cannot create settings window" << component.errors();
            delete object;
            return;
        }
    }
    if (!m_settings)
        return;
    // Mostra, traz para a frente e dá o foco.
    m_settings->show();
    m_settings->raise();
    m_settings->requestActivate();
}

void MenuController::setBlur(const QString &mode, qreal x, qreal y, qreal diameter)
{
    if (!m_overlay)
        return;
    if (mode == QLatin1String("screen")) {
        // Região vazia = a janela inteira, que aqui cobre a tela toda.
        KWindowEffects::enableBlurBehind(m_overlay, true);
    } else if (mode == QLatin1String("ring") && diameter > 0) {
        // Um quadrado em volta do anel, transformado em círculo (Ellipse).
        const QRect square(qRound(x - diameter / 2), qRound(y - diameter / 2), qRound(diameter), qRound(diameter));
        KWindowEffects::enableBlurBehind(m_overlay, true, QRegion(square, QRegion::Ellipse));
    } else {
        KWindowEffects::enableBlurBehind(m_overlay, false);
    }
}

void MenuController::activate(const QVariantMap &item)
{
    // Itens "manter aberto" (ex.: Play/Pause) rodam na hora e o menu continua
    // na tela, para o usuário apertar outro botão ou sair quando quiser.
    if (keepsOpen(item)) {
        execute(item);
        return;
    }
    hide();
    // singleShot roda a função uma única vez, depois do tempo indicado, sem
    // travar o programa enquanto espera.
    QTimer::singleShot(executeDelayMs, this, [this, item] {
        execute(item);
    });
}

bool MenuController::keepsOpen(const QVariantMap &item) const
{
    // Se o usuário marcou ou desmarcou a opção no editor, vale a escolha dele.
    const QVariant flag = item.value(QStringLiteral("keepOpen"));
    if (flag.isValid())
        return flag.toBool();
    // Sem escolha salva: os controles de mídia (Play/Pause, Próxima, Anterior…)
    // ficam abertos por padrão, porque costumam ser usados em sequência.
    const QString type = str(item, "type");
    return type == QLatin1String("media")
        || (type == QLatin1String("shortcut") && str(item, "component") == QLatin1String("/component/mediacontrol"));
}

QVariantMap MenuController::currentMenu() const
{
    const QVariantMap config = m_config->config();
    // O menu geral é sempre o mesmo (anel de fora), em qualquer app.
    QVariantMap menu{
        {QStringLiteral("items"), config.value(QStringLiteral("items")).toList()},
        {QStringLiteral("appItems"), QVariantList{}},
        {QStringLiteral("title"), QString()},
    };

    // Procura, na ordem da lista, um menu feito para o app que está em foco.
    // Se achar, os itens dele vão para o anel interno.
    const QVariantList appMenus = config.value(QStringLiteral("appMenus")).toList();
    for (const QVariant &value : appMenus) {
        const QVariantMap appMenu = value.toMap();
        if (m_windows->matches(str(appMenu, "app"))) {
            menu.insert(QStringLiteral("appItems"), appMenu.value(QStringLiteral("items")).toList());
            menu.insert(QStringLiteral("title"), str(appMenu, "name"));
            break;
        }
    }
    return menu;
}

QVariantList MenuController::openWindows() const
{
    QVariantList items;
    const QVariantList windows = m_windows->windows();
    for (const QVariant &value : windows) {
        if (items.size() >= maxWindows)
            break;
        const QVariantMap window = value.toMap();
        const QString desktopFileName = str(window, "desktopFileName");
        const QString resourceClass = str(window, "resourceClass");

        // Ícone: o do app dono da janela (pelo .desktop). Sem .desktop, tenta
        // um ícone com o nome da classe da janela e, por fim, um ícone genérico.
        QString icon = QStringLiteral("window");
        const KService::Ptr service = KService::serviceByDesktopName(desktopFileName);
        if (service && !service->icon().isEmpty())
            icon = service->icon();
        else if (QIcon::hasThemeIcon(resourceClass))
            icon = resourceClass;

        QString label = str(window, "caption");
        if (label.isEmpty())
            label = service ? service->name() : resourceClass;

        items.append(QVariantMap{
            {QStringLiteral("label"), label},
            {QStringLiteral("icon"), icon},
            {QStringLiteral("type"), QStringLiteral("window")},
            {QStringLiteral("window"), str(window, "id")},
        });
    }
    return items;
}

void MenuController::execute(const QVariantMap &item)
{
    const QString type = str(item, "type");

    if (type == QLatin1String("app")) {
        // Procura o aplicativo pelo nome do arquivo .desktop (ex.: "org.kde.konsole.desktop").
        const KService::Ptr service = KService::serviceByStorageId(str(item, "app"));
        if (!service) {
            qWarning() << "ktrackmenu: application not found:" << str(item, "app");
            return;
        }
        // Abre o app do jeito do KDE (com ícone de "carregando", ativação etc.).
        // O "job" se apaga sozinho quando termina, por isso o "new" sem "delete".
        (new KIO::ApplicationLauncherJob(service))->start();
    } else if (type == QLatin1String("command")) {
        const QString command = str(item, "command");
        // Roda o comando no shell (/bin/sh -c "comando"), a partir da pasta pessoal.
        // startDetached = o comando segue rodando por conta própria, sem prender o app.
        if (!command.isEmpty())
            QProcess::startDetached(QStringLiteral("/bin/sh"), {QStringLiteral("-c"), command}, QDir::homePath());
    } else if (type == QLatin1String("shortcut")) {
        // Aciona um atalho global do KDE, como se a tecla tivesse sido apertada.
        // "component" é quem registrou o atalho (ex.: /component/kwin) e
        // "shortcut" é o nome da ação (ex.: "Overview").
        const QString component = str(item, "component");
        const QString shortcut = str(item, "shortcut");
        if (!component.startsWith(QLatin1Char('/')) || shortcut.isEmpty())
            return;
        // Monta e envia uma mensagem D-Bus para o serviço de atalhos do KDE.
        auto msg = QDBusMessage::createMethodCall(QStringLiteral("org.kde.kglobalaccel"), component, QStringLiteral("org.kde.kglobalaccel.Component"), QStringLiteral("invokeShortcut"));
        msg << shortcut;
        QDBusConnection::sessionBus().send(msg);
    } else if (type == QLatin1String("url")) {
        QString target = str(item, "url");
        // Troca o "~" do começo pela pasta pessoal (ex.: ~/Documentos).
        if (target.startsWith(QLatin1Char('~')))
            target.replace(0, 1, QDir::homePath());
        // Aceita tanto endereços (https://...) quanto caminhos de arquivo.
        const QUrl url = QUrl::fromUserInput(target, QDir::homePath(), QUrl::AssumeLocalFile);
        // Abre com o programa padrão do sistema (navegador, Dolphin, leitor de PDF…).
        if (url.isValid())
            (new KIO::OpenUrlJob(url))->start();
    } else if (type == QLatin1String("toggle")) {
        // Liga ou desliga Wi-Fi, Bluetooth etc. (ver togglestates.cpp).
        m_toggles->toggle(str(item, "toggle"));
    } else if (type == QLatin1String("window")) {
        // Uma janela escolhida no submenu "Janelas abertas": traz ela para a frente.
        m_windows->activate(str(item, "window"));
    } else if (type == QLatin1String("media")) {
        // Play/Pause, Próxima ou Anterior no player que está tocando (ver mediaplayers.cpp).
        m_media->action(str(item, "action"));
    } else {
        qWarning() << "ktrackmenu: unknown item type" << type;
    }
}
