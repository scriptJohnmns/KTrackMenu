// =============================================================================
// mediaplayers.h — declaração da classe MediaPlayers
// =============================================================================

#pragma once

#include <QDateTime>
#include <QHash>
#include <QObject>
#include <QString>

class QDBusMessage;

// Conversa com os players de mídia abertos (Spotify, Firefox, VLC, Elisa…)
// pelo MPRIS, o padrão do Linux para controlar players pelo D-Bus.
// Cada player aberto publica um serviço "org.mpris.MediaPlayer2.<nome>" com o
// que está tocando e os comandos Play/Pause, Próxima e Anterior.
//
// Com vários players abertos, o "atual" é o que está tocando (ou, se nenhum
// estiver, o último que tocou). No QML, este objeto se chama "Media".
class MediaPlayers : public QObject
{
    Q_OBJECT
    // Q_PROPERTY deixa o QML ler o valor e ser avisado (NOTIFY) quando ele muda.
    Q_PROPERTY(bool available READ available NOTIFY changed)    // existe algum player aberto?
    Q_PROPERTY(bool playing READ playing NOTIFY changed)        // o atual está tocando?
    Q_PROPERTY(QString title READ title NOTIFY changed)         // nome da música/vídeo
    Q_PROPERTY(QString artist READ artist NOTIFY changed)       // artista(s)
    Q_PROPERTY(QString artUrl READ artUrl NOTIFY changed)       // capa do álbum ("" = sem capa)
    Q_PROPERTY(QString playerName READ playerName NOTIFY changed) // ex.: "Spotify"
    Q_PROPERTY(QString playerIcon READ playerIcon NOTIFY changed) // ícone do app do player

public:
    explicit MediaPlayers(QObject *parent = nullptr);

    bool available() const { return !m_current.isEmpty(); }
    bool playing() const { return info().status == QLatin1String("Playing"); }
    QString title() const { return info().title; }
    QString artist() const { return info().artist; }
    QString artUrl() const { return info().artUrl; }
    QString playerName() const { return info().name; }
    QString playerIcon() const { return info().icon; }

    // Manda um comando para o player atual: "playpause", "next" ou "previous".
    Q_INVOKABLE void action(const QString &name);

Q_SIGNALS:
    void changed();

private Q_SLOTS:
    // Algum player avisou que algo mudou (música, tocando/pausado…).
    void onPropertiesChanged(const QDBusMessage &message);
    // Algum serviço do D-Bus abriu, fechou ou trocou de dono.
    void onNameOwnerChanged(const QString &name, const QString &oldOwner, const QString &newOwner);

private:
    // O que sabemos de cada player.
    struct Player {
        QString owner;      // nome "único" no D-Bus (ex.: ":1.42"), usado nos avisos
        QString name;       // nome para mostrar (ex.: "Spotify")
        QString icon;       // ícone do app
        QString status;     // "Playing", "Paused" ou "Stopped"
        QString title;
        QString artist;
        QString artUrl;
        QDateTime lastPlayed; // última vez que começou a tocar (para escolher o atual)
    };

    void addPlayer(const QString &service);
    void removePlayer(const QString &service);
    // Pede ao player todas as propriedades de uma interface (sem travar o app).
    void fetch(const QString &service, const QString &interface);
    // Guarda as propriedades recebidas (do pedido acima ou de um aviso).
    void apply(const QString &service, const QVariantMap &properties);
    // Escolhe qual player é o "atual" e avisa o QML.
    void pickCurrent();
    // Dados do player atual (ou um Player vazio, se não houver nenhum).
    Player info() const { return m_players.value(m_current); }

    QHash<QString, Player> m_players; // serviço ("org.mpris.MediaPlayer2.spotify") → dados
    QString m_current;                // serviço do player atual ("" = nenhum)
};
