// =============================================================================
// windowtracker.cpp — implementação do WindowTracker (ver windowtracker.h)
//
// Caminho da informação:
//   o usuário troca de janela → o KWin roda o nosso script → o script chama
//   report() e reportWindows() por D-Bus → guardamos o app ativo e a lista →
//   ao abrir o menu, o MenuController usa matches() (anel interno do app) e
//   windows() (item "Janelas abertas").
// =============================================================================

#include "windowtracker.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusReply>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QSaveFile>
#include <QStandardPaths>

namespace
{
// Nome com que o script fica registrado dentro do KWin.
const QString scriptName = QStringLiteral("ktrackmenu-windows");

// Endereço do serviço de scripts do KWin no D-Bus.
const QString kwinService = QStringLiteral("org.kde.KWin");
const QString scriptingPath = QStringLiteral("/Scripting");
const QString scriptingInterface = QStringLiteral("org.kde.kwin.Scripting");

// O script que roda DENTRO do KWin, em JavaScript.
//  - workspace.activeWindow é a janela em foco agora
//  - workspace.windowActivated avisa toda vez que o foco muda
//  - workspace.stackingOrder é a lista de janelas, da mais atrás para a mais na frente
//  - callDBus(serviço, caminho, interface, função, argumentos...) chama o nosso C++
constexpr auto kwinScript = R"js(
// Endereço do KTrackMenu no D-Bus.
var service = "io.github.ktrackmenu", path = "/Windows", iface = "io.github.ktrackmenu.Windows";

// O menu aberto se chama "ktrackmenu"; a janela de configurações, "io.github.ktrackmenu".
function isOurs(w) {
    return w.resourceClass === "ktrackmenu" || w.resourceClass === "io.github.ktrackmenu";
}

// Avisa qual app está em foco.
function reportActive(w) {
    // Nenhuma janela, ou a área de trabalho em foco: "nenhum app".
    if (!w || w.desktopWindow) {
        callDBus(service, path, iface, "report", "", "");
        return;
    }
    // Ignora painéis, notificações etc.: só janelas comuns e caixas de diálogo.
    if ((!w.normalWindow && !w.dialog) || isOurs(w))
        return;
    callDBus(service, path, iface, "report", w.desktopFileName || "", w.resourceClass || "");
}

// Manda a lista de janelas que aparecem na barra de tarefas, da mais na
// frente para a mais atrás. "removed" é uma janela que está fechando e
// ainda pode aparecer na lista do KWin.
function reportWindows(removed) {
    var list = [];
    var all = workspace.stackingOrder;
    for (var i = all.length - 1; i >= 0; i--) {
        var w = all[i];
        if (w === removed || !w.normalWindow || w.skipTaskbar || isOurs(w))
            continue;
        list.push({ id: String(w.internalId), caption: w.caption,
                    desktopFileName: w.desktopFileName || "", resourceClass: w.resourceClass || "" });
    }
    callDBus(service, path, iface, "reportWindows", JSON.stringify(list));
}

// Quando o título de uma janela muda (ex.: outra aba no navegador), reenvia a lista.
function watch(w) {
    w.captionChanged.connect(function () { reportWindows(); });
}

workspace.stackingOrder.forEach(watch);
workspace.windowAdded.connect(function (w) { watch(w); reportWindows(); });
workspace.windowRemoved.connect(function (w) { reportWindows(w); });
// Trocar o foco também muda a ordem das janelas.
workspace.windowActivated.connect(function (w) { reportActive(w); reportWindows(); });

reportActive(workspace.activeWindow);
reportWindows();
)js";

// Deixa um id de app num formato comparável: minúsculas e sem ".desktop".
// Ex.: "org.kde.Konsole.desktop" → "org.kde.konsole"
QString normalizedId(QString id)
{
    id = id.trimmed().toLower();
    if (id.endsWith(QLatin1String(".desktop")))
        id.chop(8); // chop = corta os últimos 8 caracteres
    return id;
}
}

WindowTracker::WindowTracker(QObject *parent)
    : QObject(parent)
{
    // Publica este objeto no D-Bus em /Windows, dentro do serviço
    // io.github.ktrackmenu (registrado pelo KDBusService no main.cpp).
    QDBusConnection::sessionBus().registerObject(QStringLiteral("/Windows"), this, QDBusConnection::ExportScriptableSlots);
    loadKWinScript();
}

WindowTracker::~WindowTracker()
{
    // Ao fechar o app, tira o script do KWin para não deixar lixo para trás.
    QDBusConnection::sessionBus().call(QDBusMessage::createMethodCall(kwinService, scriptingPath, scriptingInterface, QStringLiteral("unloadScript")) << scriptName);
}

void WindowTracker::loadKWinScript()
{
    // O KWin carrega scripts a partir de um arquivo. Gravamos o texto acima em
    // ~/.local/share/ktrackmenu/windows.js
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/ktrackmenu");
    const QString file = dir + QStringLiteral("/windows.js");
    // Versões anteriores usavam outros nomes de script (e o app se chamava
    // TrackpMenu, com a pasta ~/.local/share/trackpmenu): limpa as sobras.
    for (const char *old : {"trackpmenu-activewindow", "trackpmenu-windows"}) {
        QDBusConnection::sessionBus().call(QDBusMessage::createMethodCall(kwinService, scriptingPath, scriptingInterface, QStringLiteral("unloadScript"))
                                           << QString::fromLatin1(old));
    }
    QDir(QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + QStringLiteral("/trackpmenu")).removeRecursively();
    QDir().mkpath(QFileInfo(file).absolutePath());
    QSaveFile out(file);
    if (!out.open(QIODevice::WriteOnly) || out.write(kwinScript) < 0 || !out.commit()) {
        qWarning() << "ktrackmenu: cannot write" << file;
        return;
    }

    auto bus = QDBusConnection::sessionBus();
    // Se sobrou um script de uma execução anterior (ex.: o app travou), tira antes.
    bus.call(QDBusMessage::createMethodCall(kwinService, scriptingPath, scriptingInterface, QStringLiteral("unloadScript")) << scriptName);

    // loadScript devolve um número (id); o script carregado vira o objeto
    // D-Bus /Scripting/Script<id>, que tem a função run() para iniciá-lo.
    const QDBusReply<int> id = bus.call(QDBusMessage::createMethodCall(kwinService, scriptingPath, scriptingInterface, QStringLiteral("loadScript")) << file << scriptName);
    if (!id.isValid() || id.value() < 0) {
        qWarning() << "ktrackmenu: KWin did not load the active-window script" << id.error().message();
        return;
    }
    bus.call(QDBusMessage::createMethodCall(kwinService, QStringLiteral("/Scripting/Script%1").arg(id.value()), QStringLiteral("org.kde.kwin.Script"), QStringLiteral("run")));
}

void WindowTracker::report(const QString &desktopFileName, const QString &resourceClass)
{
    m_desktopFileName = desktopFileName;
    m_resourceClass = resourceClass;
}

void WindowTracker::reportWindows(const QString &json)
{
    // Converte o texto JSON numa lista que o resto do app entende.
    m_windows = QJsonDocument::fromJson(json.toUtf8()).array().toVariantList();
}

void WindowTracker::activate(const QString &id) const
{
    if (id.isEmpty())
        return;
    // Usa o mesmo caminho do KRunner (a busca do KDE), que sabe ativar janelas:
    // "0_" + id da janela = a ação "ativar" daquela janela.
    auto msg = QDBusMessage::createMethodCall(kwinService, QStringLiteral("/WindowsRunner"), QStringLiteral("org.kde.krunner1"), QStringLiteral("Run"));
    msg << QStringLiteral("0_") + id << QString();
    QDBusConnection::sessionBus().send(msg);
}

bool WindowTracker::matches(const QString &appId) const
{
    const QString id = normalizedId(appId);
    if (id.isEmpty())
        return false;
    const QString desktop = normalizedId(m_desktopFileName);
    const QString cls = normalizedId(m_resourceClass);
    // 1) O jeito certo: o id do .desktop é igual (ex.: "org.kde.konsole").
    if (!desktop.isEmpty() && desktop == id)
        return true;
    // 2) Plano B: a classe da janela é igual ao id inteiro ou à última parte
    //    dele (ex.: app "org.mozilla.firefox" e classe "firefox").
    // section('.', -1) = o pedaço depois do último ponto.
    return !cls.isEmpty() && (cls == id || cls == id.section(QLatin1Char('.'), -1));
}
