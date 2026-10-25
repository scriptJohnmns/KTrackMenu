// =============================================================================
// mediaplayers.cpp — implementação do MediaPlayers (ver mediaplayers.h)
//
// Todo player MPRIS fica no caminho /org/mpris/MediaPlayer2 e tem duas
// interfaces que usamos:
//   org.mpris.MediaPlayer2         → Identity (nome) e DesktopEntry (para o ícone)
//   org.mpris.MediaPlayer2.Player  → PlaybackStatus, Metadata e os comandos
// =============================================================================

#include "mediaplayers.h"

#include <QDBusArgument>
#include <QDBusConnection>
#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDBusVariant>

#include <KService>

namespace
{
const QString servicePrefix = QStringLiteral("org.mpris.MediaPlayer2.");
const QString objectPath = QStringLiteral("/org/mpris/MediaPlayer2");
const QString rootInterface = QStringLiteral("org.mpris.MediaPlayer2");
const QString playerInterface = QStringLiteral("org.mpris.MediaPlayer2.Player");
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

// No D-Bus, dicionários dentro de outros valores (como o Metadata) chegam
// "embrulhados" num QDBusArgument. Esta função desembrulha se for o caso.
QVariantMap toMap(const QVariant &value)
{
    if (value.canConvert<QDBusArgument>())
        return qdbus_cast<QVariantMap>(value.value<QDBusArgument>());
    return value.toMap();
}
}

MediaPlayers::MediaPlayers(QObject *parent)
    : QObject(parent)
{
    QDBusConnection bus = QDBusConnection::sessionBus();

    // Avisa quando um player abre ou fecha. O próprio D-Bus manda o sinal
    // NameOwnerChanged para todo serviço que aparece ou some; filtramos os
    // players em onNameOwnerChanged. (O QDBusServiceWatcher com "*" não
    // percebia players abertos depois do KTrackMenu, como o Spotify.)
    bus.connect(QStringLiteral("org.freedesktop.DBus"), QStringLiteral("/org/freedesktop/DBus"), QStringLiteral("org.freedesktop.DBus"),
                QStringLiteral("NameOwnerChanged"), this, SLOT(onNameOwnerChanged(QString, QString, QString)));

    // Escuta os avisos de "propriedade mudou" de QUALQUER player (serviço vazio
    // = todos). Quem mandou o aviso é descoberto em onPropertiesChanged.
    bus.connect(QString(), objectPath, propertiesInterface, QStringLiteral("PropertiesChanged"),
                this, SLOT(onPropertiesChanged(QDBusMessage)));

    // Players que já estavam abertos antes do KTrackMenu começar.
    const QStringList names = bus.interface()->registeredServiceNames().value();
    for (const QString &name : names) {
        if (name.startsWith(servicePrefix))
            addPlayer(name);
    }
}

void MediaPlayers::addPlayer(const QString &service)
{
    Player player;
    // O nome "único" do dono do serviço: é ele que aparece como remetente dos avisos.
    player.owner = QDBusConnection::sessionBus().interface()->serviceOwner(service).value();
    // Enquanto o nome de verdade não chega, usa o fim do serviço (ex.: "spotify").
    player.name = service.mid(servicePrefix.size()).section(QLatin1Char('.'), 0, 0);
    player.icon = QStringLiteral("multimedia-player");
    m_players.insert(service, player);

    fetch(service, rootInterface);
    fetch(service, playerInterface);
}

void MediaPlayers::onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner)
{
    if (!name.startsWith(servicePrefix))
        return;
    // Dono antigo vazio = o player acabou de abrir. Dono novo vazio = fechou.
    // Os dois preenchidos = outro processo assumiu o nome: tratamos como reabrir.
    if (!oldOwner.isEmpty())
        removePlayer(name);
    if (!newOwner.isEmpty())
        addPlayer(name);
}

void MediaPlayers::removePlayer(const QString &service)
{
    if (m_players.remove(service))
        pickCurrent();
}

void MediaPlayers::fetch(const QString &service, const QString &interface)
{
    auto msg = QDBusMessage::createMethodCall(service, objectPath, propertiesInterface, QStringLiteral("GetAll"));
    msg << interface;
    // asyncCall não espera a resposta: o app continua rodando e, quando ela
    // chegar, o watcher chama a função abaixo. Assim um player travado não trava o menu.
    auto *watcher = new QDBusPendingCallWatcher(QDBusConnection::sessionBus().asyncCall(msg, 1000), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this, [this, service](QDBusPendingCallWatcher *w) {
        const QDBusPendingReply<QVariantMap> reply = *w;
        if (!reply.isError())
            apply(service, reply.value());
        w->deleteLater();
    });
}

void MediaPlayers::onPropertiesChanged(const QDBusMessage &message)
{
    // Argumentos do aviso: (interface, propriedades que mudaram, propriedades invalidadas).
    const QList<QVariant> args = message.arguments();
    if (args.size() < 2)
        return;
    const QString interface = args.at(0).toString();
    if (interface != playerInterface && interface != rootInterface)
        return;

    // Descobre de qual player veio, pelo nome único do remetente.
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it) {
        if (it->owner == message.service()) {
            apply(it.key(), toMap(args.at(1)));
            return;
        }
    }
}

void MediaPlayers::apply(const QString &service, const QVariantMap &properties)
{
    auto it = m_players.find(service);
    if (it == m_players.end())
        return;
    Player &player = *it;

    if (properties.contains(QStringLiteral("Identity")))
        player.name = properties.value(QStringLiteral("Identity")).toString();

    // DesktopEntry é o nome do .desktop do app (ex.: "spotify"), que dá o ícone dele.
    const QString desktopEntry = properties.value(QStringLiteral("DesktopEntry")).toString();
    if (!desktopEntry.isEmpty()) {
        const KService::Ptr app = KService::serviceByDesktopName(desktopEntry);
        player.icon = app && !app->icon().isEmpty() ? app->icon() : desktopEntry;
    }

    if (properties.contains(QStringLiteral("PlaybackStatus"))) {
        const QString status = properties.value(QStringLiteral("PlaybackStatus")).toString();
        // Acabou de começar a tocar: este passa a ser o player mais recente.
        if (status == QLatin1String("Playing") && player.status != status)
            player.lastPlayed = QDateTime::currentDateTime();
        player.status = status;
    }

    if (properties.contains(QStringLiteral("Metadata"))) {
        // Metadata é um dicionário com chaves padronizadas ("xesam:title" etc.).
        const QVariantMap metadata = toMap(properties.value(QStringLiteral("Metadata")));
        player.title = metadata.value(QStringLiteral("xesam:title")).toString();
        // O artista vem como lista (uma música pode ter vários).
        player.artist = metadata.value(QStringLiteral("xesam:artist")).toStringList().join(QStringLiteral(", "));
        player.artUrl = metadata.value(QStringLiteral("mpris:artUrl")).toString();
    }

    pickCurrent();
}

void MediaPlayers::pickCurrent()
{
    // Nota de cada player: tocando vale mais que pausado, que vale mais que
    // parado. Empate → o que tocou por último.
    auto rank = [](const Player &p) {
        return p.status == QLatin1String("Playing") ? 2 : p.status == QLatin1String("Paused") ? 1 : 0;
    };
    QString best;
    for (auto it = m_players.cbegin(); it != m_players.cend(); ++it) {
        if (best.isEmpty()) {
            best = it.key();
            continue;
        }
        const Player &a = *it;
        const Player &b = m_players[best];
        if (rank(a) > rank(b) || (rank(a) == rank(b) && a.lastPlayed > b.lastPlayed))
            best = it.key();
    }
    m_current = best;
    // Avisa sempre: mesmo com o mesmo player, a música ou o estado podem ter mudado.
    Q_EMIT changed();
}

void MediaPlayers::action(const QString &name)
{
    if (m_current.isEmpty())
        return;
    // Nomes dos comandos na especificação do MPRIS.
    QString method;
    if (name == QLatin1String("playpause"))
        method = QStringLiteral("PlayPause");
    else if (name == QLatin1String("next"))
        method = QStringLiteral("Next");
    else if (name == QLatin1String("previous"))
        method = QStringLiteral("Previous");
    else
        return;
    // Não espera resposta: o player avisa sozinho (PropertiesChanged) o que mudou.
    QDBusConnection::sessionBus().send(QDBusMessage::createMethodCall(m_current, objectPath, playerInterface, method));
}
