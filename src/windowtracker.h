// =============================================================================
// windowtracker.h — declaração da classe WindowTracker
// =============================================================================

#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>

// Acompanha as janelas abertas e qual aplicativo está em foco.
//
// No Wayland, por segurança, um programa comum não pode perguntar "quais
// janelas existem?" ou "qual está ativa?". Quem sabe isso é o KWin (o
// gerenciador de janelas do KDE). Por isso carregamos dentro do KWin um pequeno
// script em JavaScript que nos avisa por D-Bus, chamando:
//   report()        → a cada troca da janela em foco
//   reportWindows() → quando janelas abrem, fecham, mudam de título ou de ordem
//
// As janelas do próprio KTrackMenu (o menu e as configurações) são ignoradas:
// assim, quando o menu abre, ainda lembramos do app que estava na frente.
class WindowTracker : public QObject
{
    Q_OBJECT
    // Nome da interface D-Bus deste objeto (o script do KWin usa esse nome).
    Q_CLASSINFO("D-Bus Interface", "io.github.ktrackmenu.Windows")

public:
    explicit WindowTracker(QObject *parent = nullptr);
    // O destrutor (~) roda quando o objeto é destruído: tira o script do KWin.
    ~WindowTracker() override;

    // Diz se a janela ativa é do aplicativo "appId" (o id do .desktop guardado no
    // menu.json, ex.: "org.kde.konsole.desktop").
    bool matches(const QString &appId) const;

    // As janelas abertas, da que está mais na frente para a mais atrás:
    // [{ id, caption, desktopFileName, resourceClass }, ...]
    QVariantList windows() const { return m_windows; }

    // Traz a janela "id" para a frente (e troca de área de trabalho, se preciso).
    void activate(const QString &id) const;

public Q_SLOTS:
    // Q_SCRIPTABLE = esta função pode ser chamada por outros programas via D-Bus.
    // Quem chama é o script do KWin, sempre que outra janela ganha o foco.
    // Os dois textos vazios significam "nenhum app" (ex.: clicou na área de trabalho).
    Q_SCRIPTABLE void report(const QString &desktopFileName, const QString &resourceClass);
    // A lista de janelas, escrita em JSON pelo script (é mais simples mandar um
    // texto do que uma lista de objetos pelo D-Bus).
    Q_SCRIPTABLE void reportWindows(const QString &json);

private:
    // Grava o script num arquivo e pede ao KWin que o carregue e execute.
    void loadKWinScript();

    // Dados da janela em foco: id do .desktop (ex.: "org.kde.konsole") e
    // "classe" da janela (ex.: "firefox", plano B quando não há .desktop).
    QString m_desktopFileName;
    QString m_resourceClass;
    QVariantList m_windows;
};
