// =============================================================================
// configstore.h — declaração da classe ConfigStore
//
// Um arquivo ".h" (cabeçalho) só DECLARA o que a classe tem: nomes de funções,
// propriedades e variáveis. A implementação fica no ".cpp" de mesmo nome.
// =============================================================================

// Garante que este cabeçalho seja incluído só uma vez por compilação.
#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QVariantMap>

// Lê e grava ~/.config/trackpmenu/menu.json e recarrega o menu quando o arquivo
// muda no disco. Assim, outras ferramentas (scripts, um editor de texto, um
// servidor MCP) também podem editar o menu.
//
// QVariantMap é um "dicionário" do Qt (chave texto → valor de qualquer tipo).
// É o formato natural para guardar JSON e o QML enxerga como um objeto JavaScript.
class ConfigStore : public QObject
{
    // Q_OBJECT ativa os recursos do Qt nesta classe: sinais, propriedades e
    // acesso pelo QML. Tem que ser a primeira linha da classe.
    Q_OBJECT
    // Q_PROPERTY expõe um valor para o QML. Exemplo: "config" é lido pela função
    // config() e, quando o sinal configChanged() é emitido, o QML atualiza sozinho
    // tudo o que depende de Config.config.
    Q_PROPERTY(QVariantMap config READ config NOTIFY configChanged)
    // CONSTANT = o valor nunca muda, então não precisa de sinal.
    Q_PROPERTY(QString filePath READ filePath CONSTANT)
    // WRITE permite que o QML também altere o valor (Config.autostart = true).
    Q_PROPERTY(bool autostart READ autostart WRITE setAutostart NOTIFY autostartChanged)

public:
    // "explicit" impede conversões automáticas acidentais. "parent" é o objeto
    // dono: quando o dono é destruído, o Qt destrói os filhos junto.
    explicit ConfigStore(QObject *parent = nullptr);

    // A configuração atual (já carregada e validada).
    QVariantMap config() const { return m_config; }
    // Caminho completo do menu.json.
    QString filePath() const;

    // Q_INVOKABLE = o QML pode chamar a função diretamente (Config.save(...)).
    // Grava a configuração no disco; retorna false se não conseguir.
    Q_INVOKABLE bool save(const QVariantMap &config);
    // O menu de exemplo usado na primeira execução ou em "Restaurar menu padrão".
    Q_INVOKABLE QVariantMap defaults() const;
    // Lê o arquivo do disco de novo.
    Q_INVOKABLE void reload();

    // Iniciar junto com a sessão do KDE (liga/desliga um arquivo em ~/.config/autostart).
    bool autostart() const;
    void setAutostart(bool enabled);

// Sinais são "avisos" que a classe emite; quem estiver conectado é notificado.
Q_SIGNALS:
    void configChanged();
    void autostartChanged();

private:
    // Completa campos que faltam com os valores padrão.
    QVariantMap normalized(QVariantMap config) const;
    // (Re)começa a vigiar o arquivo e a pasta por mudanças.
    void watch();

    // Convenção do Qt/KDE: o prefixo "m_" indica uma variável membro da classe.
    QVariantMap m_config;
    // Avisa quando um arquivo ou pasta muda no disco.
    QFileSystemWatcher m_watcher;
};
