// =============================================================================
// togglestates.cpp — implementação do ToggleStates (ver togglestates.h)
//
// Cada opção conversa com uma parte diferente do sistema:
//   "wifi"       → NetworkManager, pelo D-Bus do sistema (propriedade WirelessEnabled)
//   "bluetooth"  → BlueZ, pelo D-Bus do sistema (propriedade Powered do adaptador)
//   "dnd"        → Não perturbe do Plasma, guardado em ~/.config/plasmanotifyrc
//   "nightlight" → Luz noturna do KWin, guardada em ~/.config/kwinrc
// =============================================================================

#include "togglestates.h"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusVariant>
#include <QDateTime>
#include <QProcess>
#include <QTimer>

#include <KConfigGroup>
#include <KSharedConfig>

namespace
{
const QString propertiesInterface = QStringLiteral("org.freedesktop.DBus.Properties");

// Endereços D-Bus de cada serviço: nome do serviço, caminho do objeto e interface.
const QString nmService = QStringLiteral("org.freedesktop.NetworkManager");
const QString nmPath = QStringLiteral("/org/freedesktop/NetworkManager");
const QString bluezService = QStringLiteral("org.bluez");
// O primeiro (e quase sempre único) adaptador Bluetooth do computador.
const QString bluezAdapterPath = QStringLiteral("/org/bluez/hci0");
const QString bluezAdapterInterface = QStringLiteral("org.bluez.Adapter1");

// Lê uma propriedade de um objeto D-Bus. Devolve um QVariant inválido se o
// serviço não existir (ex.: computador sem Bluetooth) ou a leitura falhar.
QVariant getDBusProperty(const QDBusConnection &bus, const QString &service, const QString &path, const QString &interface, const QString &name)
{
    auto msg = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("Get"));
    msg << interface << name;
    // Espera no máximo 500 ms pela resposta, para o menu não travar ao abrir.
    const QDBusMessage reply = bus.call(msg, QDBus::Block, 500);
    if (reply.type() != QDBusMessage::ReplyMessage || reply.arguments().isEmpty())
        return {};
    // A resposta vem "embrulhada" num QDBusVariant; variant() desembrulha.
    return reply.arguments().constFirst().value<QDBusVariant>().variant();
}

// Altera uma propriedade de um objeto D-Bus. Não espera a resposta.
void setDBusProperty(const QDBusConnection &bus, const QString &service, const QString &path, const QString &interface, const QString &name, const QVariant &value)
{
    auto msg = QDBusMessage::createMethodCall(service, path, propertiesInterface, QStringLiteral("Set"));
    msg << interface << name << QVariant::fromValue(QDBusVariant(value));
    bus.send(msg);
}

// Grupo [DoNotDisturb] do plasmanotifyrc. reparseConfiguration() relê o arquivo
// do disco, porque o próprio Plasma pode ter mudado o valor.
KConfigGroup dndGroup()
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("plasmanotifyrc"));
    config->reparseConfiguration();
    return config->group(QStringLiteral("DoNotDisturb"));
}

KConfigGroup nightLightGroup()
{
    KSharedConfig::Ptr config = KSharedConfig::openConfig(QStringLiteral("kwinrc"));
    config->reparseConfiguration();
    return config->group(QStringLiteral("NightColor"));
}
}

QVariantList ToggleStates::available() const
{
    return {
        QVariantMap{{QStringLiteral("id"), QStringLiteral("wifi")}, {QStringLiteral("name"), QStringLiteral("Wi-Fi")}, {QStringLiteral("icon"), QStringLiteral("network-wireless")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("bluetooth")}, {QStringLiteral("name"), QStringLiteral("Bluetooth")}, {QStringLiteral("icon"), QStringLiteral("preferences-system-bluetooth")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("dnd")}, {QStringLiteral("name"), QStringLiteral("Não perturbe")}, {QStringLiteral("icon"), QStringLiteral("notifications-disabled")}},
        QVariantMap{{QStringLiteral("id"), QStringLiteral("nightlight")}, {QStringLiteral("name"), QStringLiteral("Luz noturna")}, {QStringLiteral("icon"), QStringLiteral("redshift-status-on")}},
    };
}

void ToggleStates::refresh()
{
    QVariantMap states;
    const QDBusConnection system = QDBusConnection::systemBus();

    const QVariant wifi = getDBusProperty(system, nmService, nmPath, nmService, QStringLiteral("WirelessEnabled"));
    if (wifi.isValid())
        states.insert(QStringLiteral("wifi"), wifi.toBool());

    const QVariant bluetooth = getDBusProperty(system, bluezService, bluezAdapterPath, bluezAdapterInterface, QStringLiteral("Powered"));
    if (bluetooth.isValid())
        states.insert(QStringLiteral("bluetooth"), bluetooth.toBool());

    // O "Não perturbe" do Plasma é guardado como "ligado até tal data e hora".
    // Está ligado se essa data ainda não passou.
    const QDateTime until = dndGroup().readEntry("Until", QDateTime());
    states.insert(QStringLiteral("dnd"), until.isValid() && until > QDateTime::currentDateTime());

    states.insert(QStringLiteral("nightlight"), nightLightGroup().readEntry("Active", false));

    m_states = states;
    Q_EMIT statesChanged();
}

void ToggleStates::toggle(const QString &id)
{
    // Lê o estado atual antes de inverter, para não usar um valor velho.
    refresh();
    if (!m_states.contains(id)) {
        qWarning() << "ktrackmenu: toggle not available:" << id;
        return;
    }
    const bool turnOn = !m_states.value(id).toBool();
    const QDBusConnection system = QDBusConnection::systemBus();

    if (id == QLatin1String("wifi")) {
        // O NetworkManager deixa o usuário da sessão fazer isso sem senha.
        setDBusProperty(system, nmService, nmPath, nmService, QStringLiteral("WirelessEnabled"), turnOn);
    } else if (id == QLatin1String("bluetooth")) {
        if (turnOn) {
            // O Plasma desliga o Bluetooth "bloqueando" o rádio (rfkill). Com o
            // rádio bloqueado o adaptador não liga, então desbloqueia primeiro e
            // espera um pouco o adaptador ficar pronto.
            QProcess::execute(QStringLiteral("rfkill"), {QStringLiteral("unblock"), QStringLiteral("bluetooth")});
            QTimer::singleShot(300, this, [] {
                setDBusProperty(QDBusConnection::systemBus(), bluezService, bluezAdapterPath, bluezAdapterInterface, QStringLiteral("Powered"), true);
            });
        } else {
            setDBusProperty(system, bluezService, bluezAdapterPath, bluezAdapterInterface, QStringLiteral("Powered"), false);
        }
    } else if (id == QLatin1String("dnd")) {
        KConfigGroup group = dndGroup();
        // KConfig::Notify avisa o Plasma na hora que o valor mudou. Para "ligar
        // sem prazo", o próprio Plasma usa daqui a um ano; fazemos igual.
        if (turnOn)
            group.writeEntry("Until", QDateTime::currentDateTime().addYears(1), KConfig::Notify);
        else
            group.deleteEntry("Until", KConfig::Notify);
        group.sync();
    } else if (id == QLatin1String("nightlight")) {
        // O KWin percebe a mudança no kwinrc na hora (graças ao KConfig::Notify).
        KConfigGroup group = nightLightGroup();
        group.writeEntry("Active", turnOn, KConfig::Notify);
        group.sync();
    }

    m_states.insert(id, turnOn);
    Q_EMIT statesChanged();
}
