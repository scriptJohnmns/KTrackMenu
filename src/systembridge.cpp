// =============================================================================
// systembridge.cpp — implementação do SystemBridge (ver systembridge.h)
// =============================================================================

#include "systembridge.h"

#include <QCollator>
#include <QDBusConnection>
#include <QDBusMessage>
#include <QDBusObjectPath>
#include <QDBusReply>
#include <QDBusVariant>
#include <QProcess>
#include <QSysInfo>

#include <KService>
#include <kglobalaccel_version.h>

namespace
{
// Nome do serviço D-Bus do KDE que guarda todos os atalhos globais.
const QString kglobalaccelService = QStringLiteral("org.kde.kglobalaccel");
const QString componentInterface = QStringLiteral("org.kde.kglobalaccel.Component");

// Ordena uma lista de mapas pelo campo "name", sem diferenciar maiúsculas e
// respeitando acentos (QCollator segue as regras do idioma do sistema).
// "template" deixa a mesma função servir para tipos de lista diferentes.
template<typename T>
void sortByName(T &list)
{
    QCollator collator;
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(list.begin(), list.end(), [&](const QVariant &a, const QVariant &b) {
        return collator.compare(a.toMap().value(QStringLiteral("name")).toString(), b.toMap().value(QStringLiteral("name")).toString()) < 0;
    });
}
}

QVariantList SystemBridge::applications() const
{
    QVariantList apps;
    // KService lê todos os arquivos .desktop instalados (os mesmos do menu do KDE).
    const KService::List services = KService::allServices();
    for (const KService::Ptr &service : services) {
        // Pula o que não é aplicativo ou o que está escondido do menu.
        if (!service->isApplication() || service->noDisplay())
            continue;
        apps.append(QVariantMap{
            {QStringLiteral("id"), service->storageId()},
            {QStringLiteral("name"), service->name()},
            {QStringLiteral("icon"), service->icon()},
        });
    }
    sortByName(apps);
    return apps;
}

QVariantList SystemBridge::shortcutComponents() const
{
    auto bus = QDBusConnection::sessionBus();
    // Pergunta ao KDE por D-Bus: "quais componentes têm atalhos?".
    // A resposta é uma lista de caminhos como /component/kwin.
    const QDBusReply<QList<QDBusObjectPath>> paths =
        bus.call(QDBusMessage::createMethodCall(kglobalaccelService, QStringLiteral("/kglobalaccel"), QStringLiteral("org.kde.KGlobalAccel"), QStringLiteral("allComponents")));
    if (!paths.isValid())
        return {};

    QVariantList components;
    for (const QDBusObjectPath &path : paths.value()) {
        // Para cada componente, lê a propriedade "friendlyName" (nome legível).
        auto msg = QDBusMessage::createMethodCall(kglobalaccelService, path.path(), QStringLiteral("org.freedesktop.DBus.Properties"), QStringLiteral("Get"));
        msg << componentInterface << QStringLiteral("friendlyName");
        const QDBusReply<QDBusVariant> name = bus.call(msg);
        QString friendly = name.isValid() ? name.value().variant().toString() : QString();
        // Sem nome legível, usa a última parte do caminho (ex.: "kwin").
        if (friendly.isEmpty())
            friendly = path.path().section(QLatin1Char('/'), -1);
        components.append(QVariantMap{{QStringLiteral("path"), path.path()}, {QStringLiteral("name"), friendly}});
    }
    sortByName(components);
    return components;
}

QStringList SystemBridge::shortcutNames(const QString &componentPath) const
{
    // Caminhos D-Bus sempre começam com "/". Ignora valores vazios ou inválidos.
    if (!componentPath.startsWith(QLatin1Char('/')))
        return {};
    const QDBusReply<QStringList> reply =
        QDBusConnection::sessionBus().call(QDBusMessage::createMethodCall(kglobalaccelService, componentPath, componentInterface, QStringLiteral("shortcutNames")));
    QStringList names = reply.isValid() ? reply.value() : QStringList();
    names.sort(Qt::CaseInsensitive);
    return names;
}

void SystemBridge::openSystemShortcuts() const
{
    // kcm_keys é a página "Atalhos" das Configurações do sistema.
    QProcess::startDetached(QStringLiteral("systemsettings"), {QStringLiteral("kcm_keys")});
}

QVariantMap SystemBridge::aboutInfo() const
{
    return {
        {QStringLiteral("version"), QStringLiteral(TRACKPMENU_VERSION)},              // versão do app (CMakeLists.txt)
        {QStringLiteral("qt"), QString::fromLatin1(qVersion())},                      // versão do Qt em uso
        {QStringLiteral("frameworks"), QStringLiteral(KGLOBALACCEL_VERSION_STRING)},  // versão do KDE Frameworks
        {QStringLiteral("system"), QSysInfo::prettyProductName()},                    // ex.: "Fedora Linux 43"
        {QStringLiteral("kernel"), QSysInfo::kernelVersion()},
        {QStringLiteral("session"), qEnvironmentVariable("XDG_SESSION_TYPE", QStringLiteral("?"))}, // "wayland" ou "x11"
    };
}
