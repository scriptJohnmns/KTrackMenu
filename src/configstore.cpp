// =============================================================================
// configstore.cpp — implementação do ConfigStore (ver configstore.h)
//
// Formato do menu.json:
//   {
//     "version": 1,
//     "appearance": {                                    ← tamanho e visual do anel
//       "radius": 120, "itemSize": 64,                   ← tamanhos em pixels
//       "showNumbers": true, "showBorder": true,          ← números 1–9 e contornos
//       "ringOpacity": 92, "dimOpacity": 18,              ← opacidades em % (0–100)
//       "blur": "none",                                  ← "none", "ring" ou "screen"
//       "accentColor": "",                               ← cor do selecionado ("" = do tema)
//       "itemShape": "circle",                           ← "circle", "rounded" ou "square"
//       "animation": "normal"                            ← "normal", "fast" ou "off"
//     },
//     "behavior": { "holdToSelect": true },              ← segurar o atalho e soltar para escolher
//     "items": [ { "label": ..., "icon": ..., "type": ..., ... }, ... ],
//     "appMenus": [                                      ← menus por aplicativo (opcional)
//       { "app": "org.kde.konsole.desktop",              ← id do .desktop do app
//         "name": "Konsole", "icon": "utilities-terminal",
//         "items": [ ... ] }                             ← mesmo formato do "items" acima
//     ]
//   }
// Quando o menu abre com um desses apps em foco, os itens dele aparecem num
// anel interno; o menu geral continua no anel de fora (ver Overlay.qml).
// Cada item tem um "type" que diz o que ele faz:
//   "app"      → abre um aplicativo       (campo "app": id do .desktop)
//   "command"  → roda um comando de shell (campo "command")
//   "shortcut" → aciona um atalho do KDE  (campos "component" e "shortcut")
//   "url"      → abre um site ou arquivo  (campo "url")
//   "toggle"   → liga/desliga algo        (campo "toggle": "wifi", "bluetooth",
//                                          "dnd" ou "nightlight")
//   "windows"  → submenu com as janelas abertas, montado na hora (sem campos extras)
//   "menu"     → submenu                  (campo "items": outra lista de itens)
// =============================================================================

#include "configstore.h"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>

namespace
{
// Menu de exemplo, escrito direto em JSON. O R"json( ... )json" é uma "raw
// string" do C++: tudo entre os delimitadores é texto literal, sem precisar
// escapar as aspas.
constexpr auto defaultConfig = R"json({
  "version": 1,
  "appearance": { "radius": 120, "itemSize": 64, "showNumbers": true, "showBorder": true, "ringOpacity": 92, "dimOpacity": 18, "blur": "none", "accentColor": "", "itemShape": "circle", "animation": "normal" },
  "behavior": { "holdToSelect": true },
  "items": [
    { "label": "Terminal", "icon": "utilities-terminal", "type": "app", "app": "org.kde.konsole.desktop" },
    { "label": "Arquivos", "icon": "system-file-manager", "type": "app", "app": "org.kde.dolphin.desktop" },
    { "label": "Navegador", "icon": "firefox", "type": "app", "app": "org.mozilla.firefox.desktop" },
    { "label": "Visão geral", "icon": "view-app-grid", "type": "shortcut", "component": "/component/kwin", "shortcut": "Overview" },
    { "label": "Captura", "icon": "spectacle", "type": "command", "command": "spectacle -r" },
    { "label": "Mídia", "icon": "applications-multimedia", "type": "menu", "items": [
      { "label": "Play/Pause", "icon": "media-playback-start", "type": "shortcut", "component": "/component/mediacontrol", "shortcut": "playpausemedia" },
      { "label": "Próxima", "icon": "media-skip-forward", "type": "shortcut", "component": "/component/mediacontrol", "shortcut": "nextmedia" },
      { "label": "Anterior", "icon": "media-skip-backward", "type": "shortcut", "component": "/component/mediacontrol", "shortcut": "previousmedia" },
      { "label": "Mudo", "icon": "audio-volume-muted", "type": "command", "command": "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle" }
    ] },
    { "label": "Ligar/desligar", "icon": "preferences-system", "type": "menu", "items": [
      { "label": "Wi-Fi", "icon": "network-wireless", "type": "toggle", "toggle": "wifi" },
      { "label": "Bluetooth", "icon": "preferences-system-bluetooth", "type": "toggle", "toggle": "bluetooth" },
      { "label": "Não perturbe", "icon": "notifications-disabled", "type": "toggle", "toggle": "dnd" },
      { "label": "Luz noturna", "icon": "redshift-status-on", "type": "toggle", "toggle": "nightlight" }
    ] },
    { "label": "Calculadora", "icon": "accessories-calculator", "type": "app", "app": "org.kde.kcalc.desktop" },
    { "label": "Bloquear", "icon": "system-lock-screen", "type": "shortcut", "component": "/component/ksmserver", "shortcut": "Lock Session" }
  ]
})json";

// Caminho do arquivo que faz o app iniciar com a sessão:
// ~/.config/autostart/io.github.trackpmenu.desktop
QString autostartPath()
{
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/autostart/io.github.trackpmenu.desktop");
}
}

ConfigStore::ConfigStore(QObject *parent)
    : QObject(parent)
{
    // Quando o menu.json muda, recarrega o arquivo.
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] {
        reload();
        // Gravações "atômicas" (como a do QSaveFile) substituem o arquivo por um
        // novo, e o vigia perde o arquivo antigo. Por isso voltamos a vigiar.
        watch();
    });
    // Se algo muda na pasta (ex.: o arquivo foi apagado e recriado), volta a vigiar.
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] {
        watch();
    });
    reload();
    watch();
}

QString ConfigStore::filePath() const
{
    // GenericConfigLocation normalmente é ~/.config
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + QStringLiteral("/trackpmenu/menu.json");
}

QVariantMap ConfigStore::defaults() const
{
    // Converte o texto JSON acima para QVariantMap.
    return QJsonDocument::fromJson(defaultConfig).object().toVariantMap();
}

// Garante que a configuração tenha todos os campos esperados, para o resto do
// app não precisar checar se cada um existe.
QVariantMap ConfigStore::normalized(QVariantMap config) const
{
    const QVariantMap defs = defaults();
    // Para cada seção de opções, começa com os valores padrão e sobrescreve com
    // o que o usuário definiu. Assim, uma opção nova (como "behavior") já vem
    // preenchida em menus salvos por versões antigas do app.
    for (const QString &section : {QStringLiteral("appearance"), QStringLiteral("behavior")}) {
        QVariantMap merged = defs.value(section).toMap();
        const QVariantMap user = config.value(section).toMap();
        for (auto it = user.cbegin(); it != user.cend(); ++it)
            merged.insert(it.key(), it.value());
        config.insert(section, merged);
    }
    // Sem "items" ou "appMenus", usa listas vazias.
    for (const QString &list : {QStringLiteral("items"), QStringLiteral("appMenus")}) {
        if (!config.contains(list))
            config.insert(list, QVariantList{});
    }
    config.insert(QStringLiteral("version"), 1);
    return config;
}

void ConfigStore::reload()
{
    QFile file(filePath());
    // Primeira execução: o arquivo ainda não existe, então grava o menu de exemplo.
    if (!file.exists()) {
        save(defaults());
        return;
    }
    if (!file.open(QIODevice::ReadOnly)) {
        qWarning() << "trackpmenu: cannot read" << file.fileName();
        return;
    }

    QJsonParseError error;
    const QJsonDocument doc = QJsonDocument::fromJson(file.readAll(), &error);
    if (error.error != QJsonParseError::NoError || !doc.isObject()) {
        // JSON inválido (ex.: alguém salvou o arquivo no meio de uma edição):
        // mantém o menu anterior, em vez de apagar tudo.
        qWarning() << "trackpmenu: invalid JSON in" << file.fileName() << error.errorString();
        // Se ainda não havia menu nenhum carregado, usa o padrão.
        if (m_config.isEmpty()) {
            m_config = normalized(defaults());
            Q_EMIT configChanged();
        }
        return;
    }

    const QVariantMap config = normalized(doc.object().toVariantMap());
    // Só avisa o QML se algo realmente mudou (evita redesenhos à toa).
    if (config != m_config) {
        m_config = config;
        Q_EMIT configChanged();
    }
}

bool ConfigStore::save(const QVariantMap &config)
{
    const QVariantMap clean = normalized(config);
    // Cria a pasta ~/.config/trackpmenu se ela não existir.
    QDir().mkpath(QFileInfo(filePath()).absolutePath());

    // QSaveFile escreve num arquivo temporário e só substitui o original no
    // commit(). Se faltar energia no meio, o menu.json antigo continua inteiro.
    QSaveFile file(filePath());
    if (!file.open(QIODevice::WriteOnly)) {
        qWarning() << "trackpmenu: cannot write" << file.fileName();
        return false;
    }
    // Indented = JSON formatado com quebras de linha, fácil de ler e editar à mão.
    file.write(QJsonDocument(QJsonObject::fromVariantMap(clean)).toJson(QJsonDocument::Indented));
    if (!file.commit())
        return false;

    if (clean != m_config) {
        m_config = clean;
        Q_EMIT configChanged();
    }
    watch();
    return true;
}

void ConfigStore::watch()
{
    const QString path = filePath();
    const QString dir = QFileInfo(path).absolutePath();
    // Adiciona o arquivo e a pasta ao vigia, se ainda não estiverem lá.
    if (QFile::exists(path) && !m_watcher.files().contains(path))
        m_watcher.addPath(path);
    if (QFileInfo::exists(dir) && !m_watcher.directories().contains(dir))
        m_watcher.addPath(dir);
}

bool ConfigStore::autostart() const
{
    // Se o arquivo de autostart existe, o app inicia com a sessão.
    return QFile::exists(autostartPath());
}

void ConfigStore::setAutostart(bool enabled)
{
    if (enabled == autostart())
        return;

    const QString path = autostartPath();
    if (enabled) {
        QDir().mkpath(QFileInfo(path).absolutePath());
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
            return;
        // Um arquivo .desktop que o KDE executa ao entrar na sessão.
        // %1 é trocado pelo caminho deste executável; "--daemon" faz o app
        // iniciar só em segundo plano, sem abrir janela.
        file.write(QStringLiteral("[Desktop Entry]\n"
                                  "Type=Application\n"
                                  "Name=TrackpMenu\n"
                                  "Exec=%1 --daemon\n"
                                  "Icon=input-mouse\n"
                                  "NoDisplay=true\n"
                                  "X-KDE-autostart-phase=2\n")
                       .arg(QCoreApplication::applicationFilePath())
                       .toUtf8());
    } else {
        QFile::remove(path);
    }
    Q_EMIT autostartChanged();
}
