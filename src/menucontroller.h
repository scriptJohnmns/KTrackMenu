// =============================================================================
// menucontroller.h — declaração da classe MenuController
// =============================================================================

#pragma once

#include <QKeySequence>
#include <QObject>
#include <QPointer>
#include <QVariantMap>

// "Declarações antecipadas": avisam o compilador que estas classes existem, sem
// incluir o cabeçalho inteiro delas. Basta quando só usamos ponteiros para elas.
class QAction;
class QQmlEngine;
class QQuickWindow;
class WindowTracker;
class ConfigStore;
class ToggleStates;

// O "cérebro" do app. Cuida do atalho global que abre o menu, da janela
// transparente que mostra o menu radial (Overlay.qml), da janela de
// configurações e da execução da ação que o usuário escolheu.
class MenuController : public QObject
{
    Q_OBJECT
    // O QML usa "Controller.visible" para saber se o menu está aberto.
    Q_PROPERTY(bool visible READ isVisible NOTIFY visibleChanged)
    // O atalho atual, mostrado na aba Geral e na aba Sobre.
    Q_PROPERTY(QKeySequence activationShortcut READ activationShortcut NOTIFY activationShortcutChanged)

public:
    explicit MenuController(ConfigStore *config, ToggleStates *toggles, WindowTracker *windows, QObject *parent = nullptr);

    // O engine QML é necessário para criar as janelas; o main.cpp o entrega aqui.
    void setEngine(QQmlEngine *engine) { m_engine = engine; }

    bool isVisible() const;
    QKeySequence activationShortcut() const;

    // Funções que o QML (e o ícone da bandeja) podem chamar.
    Q_INVOKABLE void toggle();       // abre se estiver fechado, fecha se estiver aberto
    Q_INVOKABLE void show();         // abre o menu radial
    Q_INVOKABLE void hide();         // fecha o menu radial
    Q_INVOKABLE void openSettings(); // abre a janela de configurações

    // Executa um item "folha" (app, comando, atalho, URL ou liga/desliga). Submenus não chegam
    // aqui: a navegação entre eles é feita no próprio Overlay.qml.
    Q_INVOKABLE void activate(const QVariantMap &item);

    // O que mostrar ao abrir o menu: { items, appItems, title }.
    //   items    → o menu geral (anel de fora, sempre igual)
    //   appItems → os itens do app em foco, se houver um em "appMenus" (anel interno)
    //   title    → o nome desse app ("" se não houver)
    // O Overlay.qml chama isto toda vez que o menu abre.
    Q_INVOKABLE QVariantMap currentMenu() const;

    // Itens do tipo "Janelas abertas": monta, na hora, um submenu com uma
    // entrada (do tipo "window") para cada janela aberta.
    Q_INVOKABLE QVariantList openWindows() const;

    // Desfoque atrás do menu, feito pelo KWin. mode: "none" (sem desfoque),
    // "screen" (tela inteira) ou "ring" (só o círculo de centro (x, y) e
    // diâmetro "diameter").
    Q_INVOKABLE void setBlur(const QString &mode, qreal x, qreal y, qreal diameter);

    // Troca o atalho que abre o menu, ou volta ao padrão.
    Q_INVOKABLE void setActivationShortcut(const QKeySequence &sequence);
    Q_INVOKABLE void resetActivationShortcut();

Q_SIGNALS:
    // Pede ao Overlay.qml que se reinicie (volta ao menu principal) antes de aparecer.
    void showRequested();
    void visibleChanged();
    void activationShortcutChanged();

private:
    // Cria a janela do menu na primeira vez que for usada e a devolve.
    QQuickWindow *ensureOverlay();
    // Faz de fato o que o item pede.
    void execute(const QVariantMap &item);

    ConfigStore *m_config;
    ToggleStates *m_toggles;
    WindowTracker *m_windows;
    QQmlEngine *m_engine = nullptr;
    // A "ação" registrada no KDE como atalho global.
    QAction *m_action;
    // QPointer é um ponteiro que vira nulo sozinho se a janela for destruída,
    // evitando acessar memória que não existe mais.
    QPointer<QQuickWindow> m_overlay;
    QPointer<QQuickWindow> m_settings;
};
