// =============================================================================
// Settings.qml — a janela de configurações
//
// Quatro abas:
//   Itens do menu → lista de itens à esquerda + editor (ItemEditor.qml) à direita.
//                   No topo, escolhe-se qual menu editar: o geral ou o de um app.
//   Comportamento → atalho de ativação, "segurar e soltar", início automático
//   Aparência     → prévia ao vivo + estilos prontos, tamanho, formato, cores,
//                   transparência, desfoque e animação (componentes no fim do arquivo)
//   Sobre         → criador, versão, dicas de uso e informações do sistema
//
// Como a edição funciona: ao abrir a janela, a configuração é COPIADA para
// "draft" (rascunho). Todas as edições mexem só no rascunho; o menu.json só é
// gravado ao clicar em "Salvar". "Descartar" recarrega a versão salva.
// =============================================================================

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kquickcontrols as KQuickControls

// ApplicationWindow do Kirigami: janela padrão de apps do KDE (com notificações
// rápidas no rodapé, "pilha" de páginas etc.).
Kirigami.ApplicationWindow {
    id: win

    title: "Configurações"
    // gridUnit é a unidade de tamanho do KDE (acompanha o tamanho da fonte do sistema).
    width: Kirigami.Units.gridUnit * 52
    height: Kirigami.Units.gridUnit * 34
    minimumWidth: Kirigami.Units.gridUnit * 38
    minimumHeight: Kirigami.Units.gridUnit * 26
    visible: false    // quem mostra é o MenuController::openSettings()

    // ---- Estado da edição ----
    // Cópia de trabalho da configuração; só vai para o disco ao clicar em "Salvar".
    property var draft: ({ items: [], appearance: {} })
    property int menuIndex: -1      // menu sendo editado: -1 = menu geral; 0, 1… = posição em draft.appMenus
    property var path: []           // índices do submenu sendo editado (ex.: [5] = dentro do 6º item)
    property int current: -1        // índice do item selecionado na lista
    property bool dirty: false      // há alterações não salvas?
    property int revision: 0        // incrementado após edições no lugar, para atualizar os bindings
                                    // (mesma ideia explicada no ItemEditor.qml)

    // O menu por aplicativo sendo editado (ou null quando é o menu geral).
    readonly property var appMenu: { revision; return menuIndex >= 0 ? draft.appMenus[menuIndex] : null }

    // Itens do nível atual. O slice() cria uma cópia, para a lista da tela
    // perceber que mudou.
    readonly property var level: { revision; return levelAt(path).slice() }
    // O item selecionado (ou null).
    readonly property var currentItem: { revision; const l = levelAt(path); return current >= 0 && current < l.length ? l[current] : null }
    // "Trilha" de navegação mostrada acima da lista: Menu principal › Mídia › ...
    readonly property var crumbs: {
        revision
        const names = [appMenu ? appMenu.name : "Menu principal"]
        let list = levelAt([])
        for (const i of path) { names.push(list[i].label || "Submenu"); list = list[i].items }
        return names
    }

    // Nome legível de cada tipo, mostrado embaixo do nome do item na lista.
    readonly property var typeNames: ({ app: "Aplicativo", command: "Comando", shortcut: "Atalho do KDE", url: "Abrir URL/arquivo", toggle: "Liga/desliga", windows: "Janelas abertas", media: "Controle de mídia", menu: "Submenu" })

    // Segue o caminho "p" dentro do rascunho e devolve a lista de itens daquele nível.
    // O caminho começa nos itens do menu escolhido em "menuIndex".
    function levelAt(p) {
        let list = menuIndex >= 0 ? draft.appMenus[menuIndex].items : (draft.items || [])
        for (const i of p) list = list[i].items
        return list
    }

    // Carrega uma configuração no rascunho. JSON.parse(JSON.stringify(x)) é um
    // truque para fazer uma cópia profunda: editar o rascunho não altera o original.
    function load(config) {
        draft = JSON.parse(JSON.stringify(config))
        if (!draft.appMenus) draft.appMenus = []
        dirty = false
        selectMenu(-1)
    }

    // Passa a editar outro menu: -1 = geral; 0, 1… = um menu por aplicativo.
    function selectMenu(index) {
        menuIndex = index
        path = []
        current = levelAt([]).length ? 0 : -1
        revision++
        syncMenuBox()
    }

    // Atualiza a caixa de escolha do menu. É feito "à mão" (e não por binding)
    // porque trocar o model de um ComboBox faz ele perder o item selecionado.
    function syncMenuBox() {
        menuBox.model = ["Menu geral"].concat(draft.appMenus.map(m => m.name))
        menuBox.currentIndex = menuIndex + 1
    }

    // Cria um menu para o aplicativo "app" ({ id, name, icon }, vindo do
    // System.applications()). Se ele já tiver um menu, só seleciona o existente.
    function addAppMenu(app) {
        const existing = draft.appMenus.findIndex(m => m.app === app.id)
        if (existing >= 0) {
            selectMenu(existing)
            return
        }
        draft.appMenus.push({ app: app.id, name: app.name, icon: app.icon, items: [] })
        selectMenu(draft.appMenus.length - 1)
        changed()
    }

    // Apaga o menu por aplicativo selecionado e volta para o menu geral.
    function removeAppMenu() {
        if (menuIndex < 0) return
        draft.appMenus.splice(menuIndex, 1)
        selectMenu(-1)
        changed()
    }

    // Chamada após qualquer edição: marca como não salvo e atualiza a tela.
    function changed() {
        dirty = true
        revision++
    }

    function save() {
        if (Config.save(draft)) {
            dirty = false
            showPassiveNotification("Menu salvo")   // aviso rápido no rodapé
            return true
        }
        showPassiveNotification("Não foi possível salvar " + Config.filePath)
        return false
    }

    // Insere um item novo logo depois do selecionado.
    // splice(posição, quantosRemover, novoItem) altera a lista no lugar.
    function addItem() {
        const l = levelAt(path)
        l.splice(current + 1, 0, { label: "Novo item", icon: "", type: "command", command: "" })
        current = current + 1
        changed()
    }

    function removeItem() {
        const l = levelAt(path)
        if (current < 0) return
        l.splice(current, 1)
        current = Math.min(current, l.length - 1)
        changed()
    }

    // Move o item selecionado para cima (delta = -1) ou para baixo (delta = +1).
    function moveItem(delta) {
        const l = levelAt(path)
        const to = current + delta
        if (current < 0 || to < 0 || to >= l.length) return
        const [it] = l.splice(current, 1)   // tira da posição atual...
        l.splice(to, 0, it)                  // ...e coloca na nova
        current = to
        changed()
    }

    // Entra no submenu do item "index" para editar os itens dele.
    function enterSubmenu(index) {
        path = path.concat([index])
        current = levelAt(path).length ? 0 : -1
        revision++
    }

    // Volta para o nível "depth" da trilha (0 = menu principal), já selecionando
    // o submenu de onde se saiu.
    function goUp(depth) {
        const leaving = path[depth]
        path = path.slice(0, depth)
        current = leaving
        revision++
    }

    // Sempre que a janela aparece, recarrega a versão salva no rascunho.
    onVisibleChanged: if (visible) load(Config.config)

    // Ao fechar com alterações pendentes, cancela o fechamento e pergunta.
    onClosing: close => {
        if (dirty) {
            close.accepted = false
            unsavedDialog.open()
        }
    }

    Kirigami.PromptDialog {
        id: unsavedDialog
        title: "Alterações não salvas"
        subtitle: "Deseja salvar as alterações no menu antes de fechar?"
        standardButtons: Kirigami.Dialog.Save | Kirigami.Dialog.Discard | Kirigami.Dialog.Cancel
        onAccepted: if (win.save()) win.close()
        onDiscarded: {
            win.dirty = false
            unsavedDialog.close()
            win.close()
        }
    }

    // Barra inferior com os botões Testar / Descartar / Salvar.
    footer: QQC2.ToolBar {
        RowLayout {
            anchors.fill: parent
            QQC2.Button {
                icon.name: "input-mouse"
                text: "Testar menu"
                onClicked: Controller.show()
                QQC2.ToolTip.visible: hovered && win.dirty
                QQC2.ToolTip.text: "O teste usa a versão salva"
            }
            Item { Layout.fillWidth: true }   // espaço elástico que empurra os botões para a direita
            QQC2.Button {
                icon.name: "edit-undo"
                text: "Descartar"
                enabled: win.dirty
                onClicked: win.load(Config.config)
            }
            QQC2.Button {
                icon.name: "document-save"
                text: "Salvar"
                enabled: win.dirty
                onClicked: win.save()
            }
        }
    }

    // Janela de busca para escolher o aplicativo de um novo menu.
    Kirigami.SearchDialog {
        id: appPicker
        // Lista completa de apps instalados, carregada só na primeira vez.
        property var apps: []
        searchFieldPlaceholderText: "Buscar aplicativo…"
        emptyText: "Nenhum aplicativo encontrado"
        // Filtra pelo texto digitado, sem diferenciar maiúsculas e minúsculas.
        model: apps.filter(a => a.name.toLowerCase().includes(text.toLowerCase()))
        onOpened: {
            if (!apps.length) apps = System.applications()
            text = ""
        }
        // Enter escolhe o app destacado na lista.
        onAccepted: if (currentItem) currentItem.clicked()
        delegate: QQC2.ItemDelegate {
            required property var modelData
            width: ListView.view.width
            text: modelData.name
            icon.name: modelData.icon || "application-x-executable"
            onClicked: {
                win.addAppMenu(modelData)
                appPicker.close()
            }
        }
    }

    pageStack.initialPage: Kirigami.Page {
        title: "KTrackMenu"
        padding: 0

        header: QQC2.TabBar {
            id: tabs
            QQC2.TabButton { text: "Itens do menu"; icon.name: "view-list-details" }
            QQC2.TabButton { text: "Comportamento"; icon.name: "configure" }
            QQC2.TabButton { text: "Aparência"; icon.name: "preferences-desktop-theme-global" }
            QQC2.TabButton { text: "Sobre"; icon.name: "help-about" }
        }

        // StackLayout mostra só um filho por vez: o da aba selecionada
        // (o 1º filho é a 1ª aba, o 2º é a 2ª, e assim por diante).
        StackLayout {
            anchors.fill: parent
            currentIndex: tabs.currentIndex

            // ---- Aba "Itens do menu" ----
            RowLayout {
                spacing: 0

                // Coluna da esquerda: trilha + lista + botões
                ColumnLayout {
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 17
                    Layout.fillHeight: true
                    spacing: 0

                    // Qual menu editar: o geral ou o de um aplicativo.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        QQC2.ComboBox {
                            id: menuBox
                            Layout.fillWidth: true
                            // O model e o currentIndex são preenchidos por win.syncMenuBox().
                            // index 0 = "Menu geral", por isso o "- 1".
                            onActivated: index => win.selectMenu(index - 1)
                        }
                        QQC2.ToolButton {
                            icon.name: "list-add"
                            onClicked: appPicker.open()
                            QQC2.ToolTip.text: "Criar um menu para um aplicativo"
                            QQC2.ToolTip.visible: hovered
                        }
                        QQC2.ToolButton {
                            icon.name: "edit-delete"
                            enabled: win.menuIndex >= 0   // o menu geral não pode ser apagado
                            onClicked: win.removeAppMenu()
                            QQC2.ToolTip.text: "Apagar o menu deste aplicativo"
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    // Explicação que só aparece nos menus por aplicativo.
                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        visible: win.appMenu !== null
                        wrapMode: Text.Wrap
                        font: Kirigami.Theme.smallFont
                        opacity: 0.7
                        text: "Com " + (win.appMenu ? win.appMenu.name : "") + " em foco, estes itens aparecem num anel interno. O menu geral continua igual, no anel de fora."
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Trilha de navegação: clicar num nível anterior volta para ele.
                    Flow {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        spacing: 0
                        Repeater {
                            model: win.crumbs
                            delegate: QQC2.ToolButton {
                                required property string modelData
                                required property int index
                                text: (index > 0 ? "› " : "") + modelData
                                font.bold: index === win.crumbs.length - 1
                                enabled: index < win.crumbs.length - 1   // o nível atual não é clicável
                                onClicked: win.goUp(index)
                            }
                        }
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    QQC2.ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        // Lista dos itens do nível atual.
                        ListView {
                            id: list
                            clip: true
                            model: win.level
                            delegate: QQC2.ItemDelegate {
                                required property var modelData
                                required property int index
                                width: ListView.view.width
                                highlighted: index === win.current
                                onClicked: win.current = index
                                // Duplo clique num submenu entra nele.
                                onDoubleClicked: if (modelData.type === "menu") win.enterSubmenu(index)

                                contentItem: RowLayout {
                                    spacing: Kirigami.Units.largeSpacing
                                    Kirigami.Icon {
                                        source: modelData.icon || "application-x-executable"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        // "1. Terminal": o número é a tecla de atalho no menu.
                                        QQC2.Label {
                                            text: (index < 9 ? (index + 1) + ". " : "") + (modelData.label || "(sem nome)")
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        QQC2.Label {
                                            text: win.typeNames[modelData.type] || modelData.type
                                            font: Kirigami.Theme.smallFont
                                            opacity: 0.7
                                            Layout.fillWidth: true
                                        }
                                    }
                                    Kirigami.Icon {
                                        visible: modelData.type === "menu"
                                        source: "go-next"
                                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                                    }
                                }
                            }

                            // Mensagem quando a lista está vazia.
                            Kirigami.PlaceholderMessage {
                                anchors.centerIn: parent
                                width: parent.width - Kirigami.Units.gridUnit * 2
                                visible: list.count === 0
                                text: "Nenhum item"
                                explanation: "Use o botão + para adicionar"
                            }
                        }
                    }

                    // Aviso: com muitos itens as fatias ficam estreitas e difíceis de acertar.
                    Kirigami.InlineMessage {
                        Layout.fillWidth: true
                        Layout.margins: Kirigami.Units.smallSpacing
                        // O anel interno é menor: aperta a partir de 6 itens.
                        readonly property int limit: win.appMenu !== null && win.path.length === 0 ? 6 : 10
                        visible: list.count > limit
                        type: Kirigami.MessageType.Warning
                        text: "Mais de " + limit + " itens deixam o anel difícil de mirar. Considere um submenu."
                    }

                    Kirigami.Separator { Layout.fillWidth: true }

                    // Botões: adicionar, remover, mover para cima, mover para baixo.
                    RowLayout {
                        Layout.margins: Kirigami.Units.smallSpacing
                        QQC2.ToolButton { icon.name: "list-add"; onClicked: win.addItem(); QQC2.ToolTip.text: "Adicionar item"; QQC2.ToolTip.visible: hovered }
                        QQC2.ToolButton { icon.name: "list-remove"; enabled: win.current >= 0; onClicked: win.removeItem(); QQC2.ToolTip.text: "Remover item"; QQC2.ToolTip.visible: hovered }
                        QQC2.ToolButton { icon.name: "go-up"; enabled: win.current > 0; onClicked: win.moveItem(-1); QQC2.ToolTip.text: "Mover para cima"; QQC2.ToolTip.visible: hovered }
                        QQC2.ToolButton { icon.name: "go-down"; enabled: win.current >= 0 && win.current < list.count - 1; onClicked: win.moveItem(1); QQC2.ToolTip.text: "Mover para baixo"; QQC2.ToolTip.visible: hovered }
                    }
                }

                Kirigami.Separator { Layout.fillHeight: true }

                // Coluna da direita: o editor do item selecionado.
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth

                    ItemEditor {
                        width: parent.width
                        item: win.currentItem
                        revision: win.revision
                        onEdited: win.changed()
                        onOpenSubmenu: win.enterSubmenu(win.current)
                    }
                }
            }

            // ---- Aba "Comportamento" ----
            // Como o menu abre e como se escolhe um item.
            QQC2.ScrollView {
                contentWidth: availableWidth

                Kirigami.FormLayout {
                    width: parent.width

                    // Um Item com isSection vira um título de seção no formulário.
                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Abrir o menu" }

                    // O atalho vale na hora (não precisa de "Salvar"): quem guarda é o KDE.
                    RowLayout {
                        Kirigami.FormData.label: "Atalho:"
                        // Campo do KDE que "grava" uma combinação de teclas.
                        KQuickControls.KeySequenceItem {
                            keySequence: Controller.activationShortcut
                            modifierlessAllowed: true   // aceita tecla sozinha (ex.: Favorites)
                            checkForConflictsAgainst: KQuickControls.ShortcutType.None
                            onKeySequenceModified: Controller.setActivationShortcut(keySequence)
                        }
                        QQC2.Button {
                            text: "Padrão (tecla ★)"
                            icon.name: "edit-reset"
                            onClicked: Controller.resetActivationShortcut()
                        }
                    }

                    QQC2.Button {
                        text: "Abrir atalhos do sistema…"
                        icon.name: "preferences-desktop-keyboard-shortcut"
                        onClicked: System.openSystemShortcuts()
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Escolher um item" }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Segurar e soltar:"
                        text: "Executar o item apontado ao soltar o atalho"
                        checked: { win.revision; return win.draft.behavior ? win.draft.behavior.holdToSelect !== false : true }
                        onToggled: {
                            if (!win.draft.behavior) win.draft.behavior = {}
                            win.draft.behavior.holdToSelect = checked
                            win.changed()
                        }
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        text: "Só funciona com atalhos que usam Meta, Ctrl, Alt ou Shift (ex.: Meta+Z). Um toque rápido no atalho continua só abrindo o menu."
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Sistema" }

                    // Vale na hora (cria/apaga um arquivo em ~/.config/autostart).
                    QQC2.Switch {
                        Kirigami.FormData.label: "Iniciar com a sessão:"
                        text: "Abrir o KTrackMenu ao entrar no KDE"
                        checked: Config.autostart
                        onToggled: Config.autostart = checked
                    }

                    RowLayout {
                        Kirigami.FormData.label: "Arquivo do menu:"
                        QQC2.Label { text: Config.filePath; textFormat: Text.PlainText }
                        // Abre a pasta do menu.json no gerenciador de arquivos.
                        QQC2.ToolButton {
                            icon.name: "document-open-folder"
                            onClicked: Qt.openUrlExternally("file://" + Config.filePath.substring(0, Config.filePath.lastIndexOf("/")))
                            QQC2.ToolTip.text: "Abrir pasta"
                            QQC2.ToolTip.visible: hovered
                        }
                    }

                    // Troca o rascunho pelo menu de exemplo (ainda precisa de "Salvar").
                    QQC2.Button {
                        text: "Restaurar tudo para o padrão…"
                        icon.name: "edit-reset"
                        onClicked: {
                            win.draft = JSON.parse(JSON.stringify(Config.defaults()))
                            win.selectMenu(-1)
                            win.changed()
                        }
                        QQC2.ToolTip.text: "Itens, comportamento e aparência voltam ao padrão (só vale depois de Salvar)"
                        QQC2.ToolTip.visible: hovered
                    }
                }
            }

            // ---- Aba "Aparência" ----
            // À esquerda, uma prévia ao vivo do anel; à direita, as opções em
            // cartões. Tudo aqui vai para o rascunho: precisa de "Salvar" para valer.
            RowLayout {
                id: appearancePage
                spacing: 0

                // Cópia das opções de aparência do rascunho. É uma cópia NOVA a
                // cada edição (por causa do "revision"), para a prévia perceber a mudança.
                readonly property var values: { win.revision; return Object.assign({}, win.draft.appearance || {}) }

                // Atalhos para ler e gravar uma opção de aparência do rascunho.
                function get(key, fallback) {
                    const v = values[key]
                    return v === undefined ? fallback : v
                }
                function set(key, value) {
                    if (!win.draft.appearance) win.draft.appearance = {}
                    win.draft.appearance[key] = value
                    win.changed()
                }
                // Aplica várias opções de uma vez (usado pelos estilos prontos).
                function apply(options) {
                    if (!win.draft.appearance) win.draft.appearance = {}
                    Object.assign(win.draft.appearance, options)
                    win.changed()
                }
                // Estilo pronto: "Padrão" troca tudo pelos valores originais; os
                // outros só mudam as opções que eles listam.
                function applyPreset(preset) {
                    if (preset.name === "Padrão") {
                        win.draft.appearance = JSON.parse(JSON.stringify(preset.options))
                        win.changed()
                    } else {
                        apply(preset.options)
                    }
                }
                // Cor de destaque escolhida ("" = a do tema).
                readonly property string customAccent: get("accentColor", "")

                // Estilos prontos. "Padrão" volta tudo ao original; os outros só
                // mudam as opções listadas (a cor escolhida, por exemplo, fica).
                readonly property var presets: [
                    { name: "Padrão", options: Config.defaults().appearance },
                    { name: "Compacto", options: { radius: 90, itemSize: 48, showNumbers: false } },
                    { name: "Vidro", options: { ringOpacity: 55, blur: "ring", dimOpacity: 8, showBorder: true } },
                    { name: "Minimalista", options: { showBorder: false, showNumbers: false, dimOpacity: 0, ringOpacity: 85, blur: "none" } },
                    { name: "Grande", options: { radius: 170, itemSize: 84 } }
                ]

                // Paleta de cores de destaque (as cores do tema Breeze e algumas vizinhas).
                readonly property var palette: ["#3daee9", "#1abc9c", "#27ae60", "#fdbc4b", "#f67400", "#da4453", "#e91e63", "#8e44ad"]

                // ---- Coluna da esquerda: prévia ----
                ColumnLayout {
                    Layout.preferredWidth: Math.min(Kirigami.Units.gridUnit * 20, appearancePage.width * 0.42)
                    Layout.fillHeight: true
                    Layout.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    RingPreview {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        appearance: appearancePage.values
                        // Cantos arredondados na prévia: o layer + MultiEffect
                        // recorta o conteúdo no formato de um retângulo arredondado.
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: previewMask
                        }
                    }
                    // Máscara dos cantos arredondados da prévia (invisível).
                    Rectangle {
                        id: previewMask
                        visible: false
                        layer.enabled: true
                        width: parent.width
                        height: parent.height
                        radius: Kirigami.Units.cornerRadius * 2
                    }
                    QQC2.Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        font: Kirigami.Theme.smallFont
                        text: "Prévia ao vivo: passe o mouse nos itens. O tamanho é reduzido para caber aqui."
                    }
                }

                Kirigami.Separator { Layout.fillHeight: true }

                // ---- Coluna da direita: opções ----
                QQC2.ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: availableWidth

                    ColumnLayout {
                        width: parent.width
                        spacing: Kirigami.Units.largeSpacing

                        // Espaço no topo (o ScrollView não tem margem própria).
                        Item { implicitHeight: Kirigami.Units.smallSpacing }

                        // ---- Estilos prontos ----
                        Card {
                            title: "Estilos prontos"
                            subtitle: "Um ponto de partida. Depois, ajuste o que quiser abaixo."

                            Flow {
                                Layout.fillWidth: true
                                spacing: Kirigami.Units.smallSpacing
                                Repeater {
                                    model: appearancePage.presets
                                    delegate: Choice {
                                        required property var modelData
                                        width: Kirigami.Units.gridUnit * 5.5
                                        text: modelData.name
                                        onClicked: appearancePage.applyPreset(modelData)
                                        // Miniatura: a aparência atual com o estilo aplicado por cima.
                                        RingPreview {
                                            anchors.fill: parent
                                            interactive: false
                                            showWallpaper: false
                                            appearance: Object.assign({}, appearancePage.values, modelData.options, { blur: "none", dimOpacity: 0 })
                                        }
                                    }
                                }
                            }
                        }

                        // ---- Tamanho ----
                        Card {
                            title: "Tamanho"

                            Option {
                                label: "Raio do anel"
                                ValueSlider {
                                    from: 70; to: 320; stepSize: 10; unit: " px"
                                    value: appearancePage.get("radius", 120)
                                    onMoved: appearancePage.set("radius", value)
                                }
                            }
                            Option {
                                label: "Tamanho dos itens"
                                ValueSlider {
                                    from: 40; to: 128; stepSize: 4; unit: " px"
                                    value: appearancePage.get("itemSize", 64)
                                    onMoved: appearancePage.set("itemSize", value)
                                }
                            }
                        }

                        // ---- Itens: formato, cor, números e contornos ----
                        Card {
                            title: "Itens"

                            Option {
                                label: "Formato"
                                Repeater {
                                    model: [
                                        { value: "circle", text: "Círculo", r: 0.5 },
                                        { value: "rounded", text: "Arredondado", r: 0.25 },
                                        { value: "square", text: "Quadrado", r: 0.08 }
                                    ]
                                    delegate: Choice {
                                        id: shapeChoice
                                        required property var modelData
                                        width: Kirigami.Units.gridUnit * 4.5
                                        text: modelData.text
                                        checked: appearancePage.get("itemShape", "circle") === modelData.value
                                        onClicked: appearancePage.set("itemShape", modelData.value)
                                        // Desenho do formato.
                                        Rectangle {
                                            anchors.centerIn: parent
                                            width: Kirigami.Units.iconSizes.medium
                                            height: width
                                            radius: width * shapeChoice.modelData.r
                                            color: shapeChoice.checked ? Kirigami.Theme.highlightColor : Kirigami.Theme.disabledTextColor
                                        }
                                    }
                                }
                            }

                            Option {
                                label: "Cor de destaque"
                                hint: "Cor do item selecionado."
                                // "Tema": usa a cor de destaque do KDE.
                                Swatch {
                                    color: Kirigami.Theme.highlightColor
                                    checked: appearancePage.customAccent === ""
                                    tip: "Cor do tema do KDE"
                                    onClicked: appearancePage.set("accentColor", "")
                                }
                                Repeater {
                                    model: appearancePage.palette
                                    delegate: Swatch {
                                        required property string modelData
                                        color: modelData
                                        checked: appearancePage.customAccent.toLowerCase() === modelData
                                        onClicked: appearancePage.set("accentColor", modelData)
                                    }
                                }
                                // Outra cor qualquer, pelo seletor de cores do sistema.
                                Swatch {
                                    readonly property string custom: appearancePage.customAccent
                                    readonly property bool other: custom !== "" && !appearancePage.palette.includes(custom.toLowerCase())
                                    color: other ? custom : "transparent"
                                    checked: other
                                    tip: "Outra cor…"
                                    onClicked: {
                                        colorDialog.selectedColor = custom || Kirigami.Theme.highlightColor
                                        colorDialog.open()
                                    }
                                    Kirigami.Icon {
                                        visible: !parent.other
                                        anchors.centerIn: parent
                                        width: Kirigami.Units.iconSizes.small
                                        height: width
                                        source: "color-picker"
                                    }
                                }
                                // Janela de escolha de cor do sistema.
                                Dialogs.ColorDialog {
                                    id: colorDialog
                                    // toString() de uma cor dá "#rrggbb", que é o que vai no menu.json.
                                    onAccepted: appearancePage.set("accentColor", selectedColor.toString())
                                }
                            }

                            Option {
                                label: "Números 1–9"
                                hint: "As teclas funcionam mesmo com os números escondidos."
                                QQC2.Switch {
                                    // "Binding on" (e não "checked:") continua valendo depois
                                    // de um clique: assim um estilo pronto também mexe no botão.
                                    Binding on checked { value: appearancePage.get("showNumbers", true) }
                                    onToggled: appearancePage.set("showNumbers", checked)
                                }
                            }
                            Option {
                                label: "Contornos"
                                hint: "Borda fina no anel e nos itens."
                                QQC2.Switch {
                                    Binding on checked { value: appearancePage.get("showBorder", true) }
                                    onToggled: appearancePage.set("showBorder", checked)
                                }
                            }
                        }

                        // ---- Fundo: opacidade, escurecimento e desfoque ----
                        Card {
                            title: "Fundo"

                            Option {
                                label: "Opacidade do anel"
                                ValueSlider {
                                    from: 0; to: 100; stepSize: 1; unit: "%"
                                    value: appearancePage.get("ringOpacity", 92)
                                    onMoved: appearancePage.set("ringOpacity", value)
                                }
                            }
                            Option {
                                label: "Escurecer a tela"
                                ValueSlider {
                                    from: 0; to: 80; stepSize: 1; unit: "%"
                                    value: appearancePage.get("dimOpacity", 18)
                                    onMoved: appearancePage.set("dimOpacity", value)
                                }
                            }
                            Option {
                                label: "Desfoque"
                                hint: "Aparece melhor com a opacidade abaixo de 80%. Precisa do efeito \"Desfoque\" ativo nos efeitos do KDE."
                                Segmented {
                                    model: [
                                        { value: "none", text: "Nenhum" },
                                        { value: "ring", text: "Atrás do anel" },
                                        { value: "screen", text: "Tela inteira" }
                                    ]
                                    current: appearancePage.get("blur", "none")
                                    onPicked: value => appearancePage.set("blur", value)
                                }
                            }
                        }

                        // ---- Animação ----
                        Card {
                            title: "Animação"

                            Option {
                                label: "Velocidade"
                                Segmented {
                                    model: [
                                        { value: "normal", text: "Normal" },
                                        { value: "fast", text: "Rápida" },
                                        { value: "off", text: "Desligada" }
                                    ]
                                    current: appearancePage.get("animation", "normal")
                                    onPicked: value => appearancePage.set("animation", value)
                                }
                            }
                        }

                        Item { implicitHeight: Kirigami.Units.smallSpacing }
                    }
                }
            }

            // ---- Aba "Sobre" ----
            QQC2.ScrollView {
                id: aboutPage
                contentWidth: availableWidth

                // Dados do sistema vindos do C++ (SystemBridge::aboutInfo).
                readonly property var info: System.aboutInfo()
                // Texto copiado pelo botão "Copiar informações" (útil para relatar bugs).
                readonly property string report: "KTrackMenu " + info.version
                    + "\nSistema: " + info.system + " (kernel " + info.kernel + ", sessão " + info.session + ")"
                    + "\nQt " + info.qt + ", KDE Frameworks " + info.frameworks
                    + "\nAtalho: " + (Controller.activationShortcut.toString() || "nenhum")

                ColumnLayout {
                    width: aboutPage.availableWidth
                    spacing: Kirigami.Units.largeSpacing

                    // Cabeçalho centralizado: ícone, nome, versão, descrição e criador.
                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: Kirigami.Units.gridUnit * 2
                        spacing: Kirigami.Units.smallSpacing

                        Kirigami.Icon {
                            source: "input-mouse"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.preferredWidth: Kirigami.Units.iconSizes.enormous
                            Layout.preferredHeight: Kirigami.Units.iconSizes.enormous
                        }
                        Kirigami.Heading {
                            text: "KTrackMenu"
                            level: 1
                            Layout.alignment: Qt.AlignHCenter
                        }
                        QQC2.Label {
                            text: "Versão " + aboutPage.info.version
                            opacity: 0.7
                            Layout.alignment: Qt.AlignHCenter
                        }
                        QQC2.Label {
                            text: "Menu radial de atalhos para o KDE Plasma"
                            Layout.alignment: Qt.AlignHCenter
                        }
                        // StyledText permite tags HTML simples, como <b> para negrito.
                        QQC2.Label {
                            text: "Criado por <b>João Marcos NS</b>"
                            textFormat: Text.StyledText
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: Kirigami.Units.largeSpacing
                        }
                    }

                    Kirigami.FormLayout {
                        Layout.fillWidth: true

                        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Como usar" }

                        QQC2.Label {
                            Kirigami.FormData.label: "Abrir:"
                            text: Controller.activationShortcut.toString() || "Nenhum atalho definido (veja a aba Comportamento)"
                        }
                        QQC2.Label {
                            Kirigami.FormData.label: "Escolher:"
                            text: "Mova o cursor na direção do item e clique (ou solte o atalho), ou use as teclas 1–9"
                        }
                        QQC2.Label {
                            Kirigami.FormData.label: "Voltar/fechar:"
                            text: "Botão direito abre um submenu; clique no centro ou Backspace volta; clique fora ou Esc fecha"
                        }

                        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Sistema" }

                        QQC2.Label { Kirigami.FormData.label: "Sistema:"; text: aboutPage.info.system }
                        QQC2.Label { Kirigami.FormData.label: "Kernel:"; text: aboutPage.info.kernel }
                        QQC2.Label { Kirigami.FormData.label: "Sessão:"; text: aboutPage.info.session }
                        QQC2.Label { Kirigami.FormData.label: "Qt / Frameworks:"; text: aboutPage.info.qt + " / " + aboutPage.info.frameworks }
                        // Contador de aberturas (é ele que libera as "conquistas").
                        QQC2.Label { Kirigami.FormData.label: "Menus abertos:"; text: Controller.openCount.toLocaleString(Qt.locale(), "f", 0) }

                        RowLayout {
                            QQC2.Button {
                                text: "Copiar informações"
                                icon.name: "edit-copy"
                                // Coloca o texto num campo escondido, seleciona tudo e copia.
                                onClicked: {
                                    copyHelper.text = aboutPage.report
                                    copyHelper.selectAll()
                                    copyHelper.copy()
                                    win.showPassiveNotification("Informações copiadas")
                                }
                                QQC2.ToolTip.text: "Útil para relatar um problema"
                                QQC2.ToolTip.visible: hovered
                            }
                            QQC2.Button {
                                text: "Abrir configuração"
                                icon.name: "document-open-folder"
                                onClicked: Qt.openUrlExternally("file://" + Config.filePath.substring(0, Config.filePath.lastIndexOf("/")))
                            }
                        }

                        // Campo de texto invisível usado só para copiar: o QML não tem
                        // uma forma direta de acessar a área de transferência fora de
                        // campos de texto.
                        TextEdit { id: copyHelper; visible: false }
                    }
                }
            }
        }
    }

    // =========================================================================
    // Componentes da aba Aparência
    // "component Nome: Tipo { ... }" cria um tipo novo, usado só neste arquivo.
    // "default property alias content: x.data" faz os filhos escritos dentro do
    // componente irem parar dentro de "x".
    // =========================================================================

    // Cartão: caixa com título (e subtítulo opcional) que agrupa opções.
    component Card: Rectangle {
        property string title
        property string subtitle
        default property alias content: body.data

        Layout.fillWidth: true
        Layout.leftMargin: Kirigami.Units.largeSpacing
        Layout.rightMargin: Kirigami.Units.largeSpacing
        implicitHeight: column.implicitHeight + 2 * Kirigami.Units.largeSpacing
        radius: Kirigami.Units.cornerRadius * 2
        // Cores de "área de conteúdo" do tema, um pouco diferentes do fundo da janela.
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false
        color: Kirigami.Theme.backgroundColor
        border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.12)

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            spacing: Kirigami.Units.largeSpacing

            ColumnLayout {
                spacing: 0
                Kirigami.Heading { level: 4; text: title }
                QQC2.Label {
                    visible: subtitle !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    opacity: 0.7
                    text: subtitle
                }
            }
            ColumnLayout {
                id: body
                Layout.fillWidth: true
                spacing: Kirigami.Units.largeSpacing
            }
        }
    }

    // Linha de opção: nome (e explicação curta) à esquerda, controle à direita.
    // A coluna da esquerda tem largura fixa, então os controles ficam alinhados.
    component Option: RowLayout {
        property string label
        property string hint
        default property alias content: control.data

        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing

        ColumnLayout {
            Layout.preferredWidth: Kirigami.Units.gridUnit * 9
            Layout.maximumWidth: Kirigami.Units.gridUnit * 9
            Layout.alignment: Qt.AlignTop
            spacing: 0
            QQC2.Label { Layout.fillWidth: true; text: label; wrapMode: Text.Wrap }
            QQC2.Label {
                visible: hint !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                opacity: 0.6
                font: Kirigami.Theme.smallFont
                text: hint
            }
        }
        // Flow quebra a linha se os controles não couberem (ex.: as bolinhas de cor).
        Flow {
            id: control
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
        }
    }

    // Controle deslizante com o valor escrito ao lado (ex.: "120 px").
    // "moved(value)" avisa quando o USUÁRIO arrasta.
    component ValueSlider: RowLayout {
        id: valueSlider
        property real from: 0
        property real to: 100
        property real stepSize: 1
        property real value: 0
        property string unit: ""
        signal moved(real value)

        width: parent ? parent.width : implicitWidth
        QQC2.Slider {
            id: slider
            Layout.fillWidth: true
            from: valueSlider.from
            to: valueSlider.to
            stepSize: valueSlider.stepSize
            // Binding (e não "value:") continua valendo depois de o usuário
            // arrastar; "when" evita brigar com o dedo enquanto arrasta.
            Binding on value { value: valueSlider.value; when: !slider.pressed }
            onMoved: valueSlider.moved(value)
        }
        QQC2.Label {
            Layout.minimumWidth: Kirigami.Units.gridUnit * 3
            horizontalAlignment: Text.AlignRight
            text: Math.round(slider.value) + valueSlider.unit
            font.features: { "tnum": 1 }   // algarismos de largura igual: o texto não "pula"
        }
    }

    // Bloco clicável com um desenho em cima e um nome embaixo (estilos e formatos).
    // O desenho vai dentro do bloco, como filho.
    component Choice: QQC2.AbstractButton {
        id: choice
        default property alias content: drawing.data
        implicitHeight: Kirigami.Units.gridUnit * 5
        hoverEnabled: true

        background: Rectangle {
            radius: Kirigami.Units.cornerRadius * 2
            color: choice.checked ? Qt.rgba(Kirigami.Theme.highlightColor.r, Kirigami.Theme.highlightColor.g, Kirigami.Theme.highlightColor.b, 0.15)
                 : choice.hovered ? Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.06)
                 : "transparent"
            border.width: choice.checked ? 2 : 1
            border.color: choice.checked || choice.hovered ? Kirigami.Theme.highlightColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
        }
        contentItem: ColumnLayout {
            spacing: 2
            Item {
                id: drawing
                Layout.fillWidth: true
                Layout.fillHeight: true
            }
            QQC2.Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: choice.text
                font: Kirigami.Theme.smallFont
            }
        }
        padding: Kirigami.Units.smallSpacing
    }

    // Bolinha de cor clicável. Selecionada, ganha um anel em volta.
    component Swatch: QQC2.AbstractButton {
        id: swatch
        property color color
        property string tip
        implicitWidth: Kirigami.Units.iconSizes.medium
        implicitHeight: implicitWidth
        hoverEnabled: true
        QQC2.ToolTip.text: tip || color.toString()
        QQC2.ToolTip.visible: hovered
        QQC2.ToolTip.delay: Kirigami.Units.toolTipDelay

        background: Rectangle {
            radius: width / 2
            color: swatch.color
            // Anel de seleção (cor do texto) ou contorno fino.
            border.width: swatch.checked ? 3 : 1
            border.color: swatch.checked ? Kirigami.Theme.textColor
                        : Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, swatch.hovered ? 0.6 : 0.2)
        }
    }

    // Botões lado a lado em que só um fica marcado (como abas pequenas).
    // model: [{ value, text }, ...]; "current" diz qual está marcado.
    component Segmented: Row {
        id: segmented
        property var model: []
        property string current
        signal picked(string value)
        spacing: 0
        Repeater {
            model: segmented.model
            delegate: QQC2.Button {
                required property var modelData
                text: modelData.text
                checkable: true
                checked: segmented.current === modelData.value
                onClicked: {
                    segmented.picked(modelData.value)
                    // O clique inverte "checked" sozinho e desfaz o binding acima.
                    // Qt.binding recoloca a regra: marcado = é o valor atual.
                    checked = Qt.binding(() => segmented.current === modelData.value)
                }
            }
        }
    }
}
