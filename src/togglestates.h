// =============================================================================
// togglestates.h — declaração da classe ToggleStates
// =============================================================================

#pragma once

#include <QObject>
#include <QVariantList>
#include <QVariantMap>

// Cuida dos itens "liga/desliga" do menu: Wi-Fi, Bluetooth, Não perturbe e
// Luz noturna. Sabe ler se cada um está ligado e sabe inverter o estado.
// No QML, este objeto se chama "Toggles".
class ToggleStates : public QObject
{
    Q_OBJECT
    // Estado de cada opção, por exemplo { wifi: true, bluetooth: false, ... }.
    // Uma opção que não existe neste computador simplesmente não aparece no mapa.
    Q_PROPERTY(QVariantMap states READ states NOTIFY statesChanged)

public:
    // Reaproveita o construtor do QObject (só recebe o "parent").
    using QObject::QObject;

    QVariantMap states() const { return m_states; }

    // Lista das opções que existem: [{ id, name, icon }, ...]. Usada pelo
    // editor de itens e para preencher nome e ícone automaticamente.
    Q_INVOKABLE QVariantList available() const;
    // Relê o estado de todas as opções (o menu chama ao abrir).
    Q_INVOKABLE void refresh();
    // Inverte o estado de uma opção ("wifi", "bluetooth", "dnd" ou "nightlight").
    Q_INVOKABLE void toggle(const QString &id);

Q_SIGNALS:
    void statesChanged();

private:
    QVariantMap m_states;
};
