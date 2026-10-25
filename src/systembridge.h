// =============================================================================
// systembridge.h — declaração da classe SystemBridge
// =============================================================================

#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

// "Ponte" entre a tela de configurações e o sistema. Responde a perguntas como
// "quais apps estão instalados?" e "quais atalhos do KDE existem?".
// No QML, este objeto se chama "System".
class SystemBridge : public QObject
{
    Q_OBJECT

public:
    // Reaproveita o construtor do QObject (só recebe o "parent").
    using QObject::QObject;

    // Lista de apps instalados: [{ id, name, icon }, ...], em ordem alfabética.
    Q_INVOKABLE QVariantList applications() const;
    // Lista de "componentes" com atalhos globais (KWin, Spectacle…): [{ path, name }, ...].
    Q_INVOKABLE QVariantList shortcutComponents() const;
    // Nomes das ações de atalho de um componente (ex.: "Overview" do KWin).
    Q_INVOKABLE QStringList shortcutNames(const QString &componentPath) const;

    // Abre Configurações do sistema → Atalhos.
    Q_INVOKABLE void openSystemShortcuts() const;

    // Versões e dados da sessão, mostrados na aba "Sobre" e copiados em relatos de bug.
    Q_INVOKABLE QVariantMap aboutInfo() const;
};
