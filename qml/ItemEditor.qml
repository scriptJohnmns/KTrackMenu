// =============================================================================
// ItemEditor.qml — formulário que edita UM item do menu
//
// Aparece à direita na aba "Itens do menu" (Settings.qml). Mostra campos
// diferentes conforme o tipo do item (app, comando, atalho, URL, liga/desliga,
// janelas abertas ou submenu).
//
// Importante: "item" é um objeto JavaScript que pertence à cópia de trabalho
// do Settings.qml. Este editor altera esse objeto diretamente ("no lugar") e
// emite edited() para avisar que algo mudou. Nada vai para o disco até o
// usuário clicar em "Salvar".
// =============================================================================

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.iconthemes as KIconThemes

// FormLayout é o formulário padrão do KDE: rótulos à esquerda, campos à direita.
Kirigami.FormLayout {
    id: editor

    property var item: null       // o item sendo editado (null = nenhum selecionado)
    property int revision: 0      // contador vindo do Settings.qml (explicado abaixo)

    signal edited()               // "alterei o item"
    signal openSubmenu()          // "o usuário quer editar os itens do submenu"

    // Listas carregadas só quando forem usadas pela primeira vez, porque
    // consultar todos os apps e atalhos do sistema demora um pouco.
    property var apps: null
    property var components: null

    // Por que "revision"? Como o item é alterado no lugar, o QML não percebe a
    // mudança sozinho. Mencionar "revision" num binding faz o binding depender
    // dele, e o Settings.qml incrementa revision depois de cada edição, o que
    // força tudo a se recalcular.
    readonly property string type: { revision; return item ? item.type : "" }

    // Lê um campo do item (ou "" se não existir).
    function field(name) {
        revision
        return item && item[name] !== undefined ? item[name] : ""
    }

    // Altera um campo do item e avisa, se o valor realmente mudou.
    function set(name, value) {
        if (!item || item[name] === value) return
        item[name] = value
        edited()
    }

    // Sem item selecionado, o formulário fica desativado (acinzentado).
    enabled: item !== null

    // Ao trocar de tipo, carrega a lista que esse tipo precisa (só na primeira vez).
    onTypeChanged: {
        if (type === "app" && apps === null) apps = System.applications()
        if (type === "shortcut" && components === null) components = System.shortcutComponents()
    }

    Kirigami.PlaceholderMessage {
        visible: editor.item === null
        Kirigami.FormData.isSection: true
        text: "Selecione um item"
    }

    // ---- Campos comuns a todos os tipos ----

    QQC2.TextField {
        Kirigami.FormData.label: "Nome:"
        visible: editor.item !== null
        text: editor.field("label")
        // onTextEdited só dispara quando o USUÁRIO digita (e não quando o texto
        // muda por causa do binding acima), evitando um laço infinito.
        onTextEdited: editor.set("label", text)
    }

    RowLayout {
        Kirigami.FormData.label: "Ícone:"
        visible: editor.item !== null

        // Prévia do ícone.
        Kirigami.Icon {
            source: editor.field("icon") || "application-x-executable"
            Layout.preferredWidth: Kirigami.Units.iconSizes.medium
            Layout.preferredHeight: Kirigami.Units.iconSizes.medium
        }
        // O nome do ícone também pode ser digitado à mão.
        QQC2.TextField {
            text: editor.field("icon")
            placeholderText: "nome-do-ícone"
            onTextEdited: editor.set("icon", text)
        }
        QQC2.Button {
            text: "Escolher…"
            icon.name: "document-open"
            onClicked: iconDialog.open()
        }
        // O seletor de ícones do KDE. É ele que exige QApplication no main.cpp.
        KIconThemes.IconDialog {
            id: iconDialog
            onIconNameChanged: if (iconName) editor.set("icon", iconName)
        }
    }

    QQC2.ComboBox {
        id: typeBox
        Kirigami.FormData.label: "Tipo:"
        visible: editor.item !== null
        // Cada opção tem um valor interno (value) e um texto visível (text).
        textRole: "text"
        valueRole: "value"
        model: [
            { value: "app", text: "Abrir aplicativo" },
            { value: "command", text: "Executar comando" },
            { value: "shortcut", text: "Acionar atalho do KDE" },
            { value: "url", text: "Abrir URL ou arquivo" },
            { value: "toggle", text: "Ligar/desligar (Wi-Fi, Bluetooth…)" },
            { value: "windows", text: "Janelas abertas" },
            { value: "menu", text: "Submenu" }
        ]
        currentIndex: indexOfValue(editor.type)
        // onActivated = o usuário escolheu uma opção na lista.
        onActivated: {
            if (editor.type === currentValue) return
            editor.item.type = currentValue
            // "Janelas abertas" já ganha nome e ícone prontos, se ainda não tiver.
            if (currentValue === "windows") {
                if (!editor.item.label || editor.item.label === "Novo item") editor.item.label = "Janelas"
                if (!editor.item.icon) editor.item.icon = "preferences-system-windows"
            }
            // Um submenu precisa de uma lista de itens, mesmo que vazia.
            if (currentValue === "menu" && !editor.item.items) editor.item.items = []
            editor.edited()
        }
    }

    // Linha separadora entre os campos comuns e os específicos do tipo.
    Item { Kirigami.FormData.isSection: true; visible: editor.item !== null }

    // ---- Tipo "app": escolher um aplicativo instalado ----
    QQC2.ComboBox {
        id: appBox
        Kirigami.FormData.label: "Aplicativo:"
        visible: editor.type === "app"
        Layout.fillWidth: true
        model: editor.apps || []
        textRole: "name"
        valueRole: "id"
        currentIndex: { editor.revision; return editor.apps ? indexOfValue(editor.field("app")) : -1 }
        // Se o app salvo não está na lista (ex.: foi desinstalado), mostra o id cru.
        displayText: currentIndex < 0 ? (editor.field("app") || "Escolha um aplicativo") : currentText
        // Cada linha da lista suspensa mostra o ícone e o nome do app.
        delegate: QQC2.ItemDelegate {
            required property var modelData
            required property int index
            width: appBox.popup.width
            text: modelData.name
            icon.name: modelData.icon
            highlighted: appBox.highlightedIndex === index
        }
        onActivated: index => {
            const app = editor.apps[index]
            const oldApp = (editor.apps || []).find(a => a.id === editor.item.app)
            // O nome e o ícone acompanham o app escolhido, a não ser que o usuário
            // já os tenha personalizado (diferentes dos do app anterior).
            if (!editor.item.label || editor.item.label === "Novo item" || (oldApp && editor.item.label === oldApp.name))
                editor.item.label = app.name
            if (!editor.item.icon || (oldApp && editor.item.icon === oldApp.icon))
                editor.item.icon = app.icon
            editor.item.app = app.id
            editor.edited()
        }
    }

    // ---- Tipo "command": comando de shell ----
    QQC2.TextField {
        Kirigami.FormData.label: "Comando:"
        visible: editor.type === "command"
        Layout.fillWidth: true
        font.family: "monospace"
        placeholderText: "ex.: playerctl play-pause"
        text: editor.field("command")
        onTextEdited: editor.set("command", text)
    }

    // Lista de comandos prontos que preenchem o campo acima.
    QQC2.ComboBox {
        Kirigami.FormData.label: "Modelos:"
        visible: editor.type === "command"
        displayText: "Inserir um modelo…"
        textRole: "text"
        model: [
            { text: "Silenciar áudio", cmd: "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle", icon: "audio-volume-muted" },
            { text: "Volume +5%", cmd: "wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ 5%+", icon: "audio-volume-high" },
            { text: "Volume -5%", cmd: "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-", icon: "audio-volume-low" },
            { text: "Captura de região", cmd: "spectacle -r", icon: "spectacle" },
            { text: "Bloquear tela", cmd: "loginctl lock-session", icon: "system-lock-screen" },
            { text: "Suspender", cmd: "systemctl suspend", icon: "system-suspend" },
            { text: "Seletor de cores", cmd: "kcolorchooser", icon: "color-picker" }
        ]
        onActivated: index => {
            const preset = model[index]
            editor.item.command = preset.cmd
            // Só preenche nome e ícone se ainda estiverem vazios/genéricos.
            if (!editor.item.label || editor.item.label === "Novo item") editor.item.label = preset.text
            if (!editor.item.icon) editor.item.icon = preset.icon
            editor.edited()
        }
    }

    QQC2.Label {
        visible: editor.type === "command"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: "Executado com /bin/sh -c na sua pasta pessoal. Para simular teclas, use por exemplo o ydotool."
    }

    // ---- Tipo "shortcut": acionar um atalho global do KDE ----
    // Primeiro escolhe-se o componente (KWin, Spectacle…), depois a ação.
    QQC2.ComboBox {
        id: componentBox
        Kirigami.FormData.label: "Componente:"
        visible: editor.type === "shortcut"
        Layout.fillWidth: true
        model: editor.components || []
        textRole: "name"
        valueRole: "path"
        currentIndex: { editor.revision; return editor.components ? indexOfValue(editor.field("component")) : -1 }
        displayText: currentIndex < 0 ? (editor.field("component") || "Escolha um componente") : currentText
        onActivated: {
            editor.item.component = currentValue
            // Trocou de componente: a ação escolhida antes não vale mais.
            editor.item.shortcut = ""
            editor.edited()
        }
    }

    QQC2.ComboBox {
        Kirigami.FormData.label: "Ação:"
        visible: editor.type === "shortcut"
        Layout.fillWidth: true
        // Pergunta ao C++ as ações do componente escolhido (atualiza ao trocar).
        model: { editor.revision; return editor.type === "shortcut" ? System.shortcutNames(editor.field("component")) : [] }
        currentIndex: { editor.revision; return model.indexOf(editor.field("shortcut")) }
        displayText: currentIndex < 0 ? (editor.field("shortcut") || "Escolha uma ação") : currentText
        onActivated: index => {
            const name = model[index]
            if (!editor.item.label || editor.item.label === "Novo item") editor.item.label = name
            editor.item.shortcut = name
            editor.edited()
        }
    }

    // ---- Tipo "url": site ou arquivo ----
    QQC2.TextField {
        Kirigami.FormData.label: "Endereço:"
        visible: editor.type === "url"
        Layout.fillWidth: true
        placeholderText: "https://… ou ~/Documentos"
        text: editor.field("url")
        onTextEdited: editor.set("url", text)
    }

    // ---- Tipo "toggle": ligar/desligar Wi-Fi, Bluetooth, Não perturbe ou Luz noturna ----
    QQC2.ComboBox {
        Kirigami.FormData.label: "Opção:"
        visible: editor.type === "toggle"
        Layout.fillWidth: true
        // A lista vem do C++ (togglestates.cpp): [{ id, name, icon }, ...].
        model: Toggles.available()
        textRole: "name"
        valueRole: "id"
        currentIndex: { editor.revision; return indexOfValue(editor.field("toggle")) }
        displayText: currentIndex < 0 ? "Escolha uma opção" : currentText
        onActivated: index => {
            const option = model[index]
            const old = model.find(o => o.id === editor.item.toggle)
            // Nome e ícone acompanham a opção, como no tipo "app".
            if (!editor.item.label || editor.item.label === "Novo item" || (old && editor.item.label === old.name))
                editor.item.label = option.name
            if (!editor.item.icon || (old && editor.item.icon === old.icon))
                editor.item.icon = option.icon
            editor.item.toggle = option.id
            editor.edited()
        }
    }

    QQC2.Label {
        visible: editor.type === "toggle"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: "No menu, uma bolinha verde no canto do item mostra que está ligado."
    }

    // ---- Tipo "windows": submenu automático com as janelas abertas ----
    QQC2.Label {
        visible: editor.type === "windows"
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        opacity: 0.7
        text: "Abre um submenu com as janelas abertas (até 12, da mais recente para a mais antiga). Escolher uma traz ela para a frente."
    }

    // ---- Tipo "menu": submenu ----
    // Os itens do submenu são editados na própria lista da esquerda (entrando nele).
    QQC2.Button {
        Kirigami.FormData.label: "Itens:"
        visible: editor.type === "menu"
        text: { editor.revision; const n = editor.item && editor.item.items ? editor.item.items.length : 0; return "Editar submenu (" + n + " itens)" }
        icon.name: "go-next"
        onClicked: editor.openSubmenu()
    }
}
