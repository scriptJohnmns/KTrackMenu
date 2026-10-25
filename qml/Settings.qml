// =============================================================================
// Settings.qml — a janela de configurações
//
// Quatro abas:
//   Itens do menu → lista de itens à esquerda + editor (ItemEditor.qml) à direita.
//                   No topo, escolhe-se qual menu editar: o geral ou o de um app.
//   Comportamento → atalho de ativação, "segurar e soltar", início automático
//   Aparência     → tamanho, formato, cores, transparência, desfoque e animação
//   Sobre         → criador, versão, dicas de uso e informações do sistema
//
// Como a edição funciona: ao abrir a janela, a configuração é COPIADA para
// "draft" (rascunho). Todas as edições mexem só no rascunho; o menu.json só é
// gravado ao clicar em "Salvar". "Descartar" recarrega a versão salva.
// =============================================================================

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Dialogs as Dialogs
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
    readonly property var typeNames: ({ app: "Aplicativo", command: "Comando", shortcut: "Atalho do KDE", url: "Abrir URL/arquivo", toggle: "Liga/desliga", windows: "Janelas abertas", menu: "Submenu" })

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
        title: "TrackpMenu"
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
                        text: "Abrir o TrackpMenu ao entrar no KDE"
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
            // Tudo aqui vai para o rascunho: precisa de "Salvar" para valer.
            QQC2.ScrollView {
                id: appearancePage
                contentWidth: availableWidth

                // Atalhos para ler e gravar uma opção de aparência do rascunho.
                function get(key, fallback) {
                    win.revision
                    const v = win.draft.appearance ? win.draft.appearance[key] : undefined
                    return v === undefined ? fallback : v
                }
                function set(key, value) {
                    if (!win.draft.appearance) win.draft.appearance = {}
                    win.draft.appearance[key] = value
                    win.changed()
                }

                Kirigami.FormLayout {
                    width: parent.width

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Tamanho" }

                    QQC2.SpinBox {
                        Kirigami.FormData.label: "Raio do anel (px):"
                        from: 70; to: 320; stepSize: 10
                        value: appearancePage.get("radius", 120)
                        onValueModified: appearancePage.set("radius", value)
                    }

                    QQC2.SpinBox {
                        Kirigami.FormData.label: "Tamanho dos itens (px):"
                        from: 40; to: 128; stepSize: 4
                        value: appearancePage.get("itemSize", 64)
                        onValueModified: appearancePage.set("itemSize", value)
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Itens" }

                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Formato:"
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            { value: "circle", text: "Círculo" },
                            { value: "rounded", text: "Cantos arredondados" },
                            { value: "square", text: "Quadrado" }
                        ]
                        currentIndex: Math.max(0, indexOfValue(appearancePage.get("itemShape", "circle")))
                        onActivated: appearancePage.set("itemShape", currentValue)
                    }

                    // Cor do item selecionado. Vazio = cor de destaque do tema do KDE.
                    RowLayout {
                        Kirigami.FormData.label: "Cor de destaque:"
                        readonly property string custom: appearancePage.get("accentColor", "")
                        // Quadradinho com a cor atual.
                        Rectangle {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Layout.preferredWidth
                            radius: 4
                            color: parent.custom || Kirigami.Theme.highlightColor
                            border.color: Kirigami.Theme.textColor
                            border.width: 1
                        }
                        QQC2.Button {
                            text: "Escolher…"
                            icon.name: "color-picker"
                            onClicked: {
                                colorDialog.selectedColor = parent.custom || Kirigami.Theme.highlightColor
                                colorDialog.open()
                            }
                        }
                        QQC2.Button {
                            text: "Usar a do tema"
                            icon.name: "edit-reset"
                            enabled: parent.custom !== ""
                            onClicked: appearancePage.set("accentColor", "")
                        }
                        // Janela de escolha de cor do sistema.
                        Dialogs.ColorDialog {
                            id: colorDialog
                            // toString() de uma cor dá "#rrggbb", que é o que vai no menu.json.
                            onAccepted: appearancePage.set("accentColor", selectedColor.toString())
                        }
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Números:"
                        text: "Mostrar os números 1–9 (as teclas funcionam mesmo escondidos)"
                        checked: appearancePage.get("showNumbers", true)
                        onToggled: appearancePage.set("showNumbers", checked)
                    }

                    QQC2.Switch {
                        Kirigami.FormData.label: "Contornos:"
                        text: "Mostrar a borda do anel e dos itens"
                        checked: appearancePage.get("showBorder", true)
                        onToggled: appearancePage.set("showBorder", checked)
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Transparência e fundo" }

                    // Controle deslizante com o valor em % ao lado.
                    RowLayout {
                        Kirigami.FormData.label: "Opacidade do anel:"
                        QQC2.Slider {
                            id: ringOpacitySlider
                            from: 0; to: 100; stepSize: 1
                            value: appearancePage.get("ringOpacity", 92)
                            // onMoved só dispara quando o USUÁRIO arrasta.
                            onMoved: appearancePage.set("ringOpacity", value)
                        }
                        QQC2.Label { text: Math.round(ringOpacitySlider.value) + "%" }
                    }

                    RowLayout {
                        Kirigami.FormData.label: "Escurecer a tela:"
                        QQC2.Slider {
                            id: dimSlider
                            from: 0; to: 80; stepSize: 1
                            value: appearancePage.get("dimOpacity", 18)
                            onMoved: appearancePage.set("dimOpacity", value)
                        }
                        QQC2.Label { text: Math.round(dimSlider.value) + "%" }
                    }

                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Desfoque (blur):"
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            { value: "none", text: "Nenhum" },
                            { value: "ring", text: "Atrás do anel" },
                            { value: "screen", text: "Tela inteira" }
                        ]
                        currentIndex: Math.max(0, indexOfValue(appearancePage.get("blur", "none")))
                        onActivated: appearancePage.set("blur", currentValue)
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        wrapMode: Text.Wrap
                        opacity: 0.7
                        text: "O desfoque aparece melhor com a opacidade do anel abaixo de 80%. Ele depende do efeito \"Desfoque\" estar ativo nos efeitos da área de trabalho do KDE."
                    }

                    Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Animação" }

                    QQC2.ComboBox {
                        Kirigami.FormData.label: "Animações:"
                        textRole: "text"
                        valueRole: "value"
                        model: [
                            { value: "normal", text: "Normais" },
                            { value: "fast", text: "Rápidas" },
                            { value: "off", text: "Desligadas" }
                        ]
                        currentIndex: Math.max(0, indexOfValue(appearancePage.get("animation", "normal")))
                        onActivated: appearancePage.set("animation", currentValue)
                    }

                    // Só a seção "appearance" volta ao padrão; os itens ficam como estão.
                    QQC2.Button {
                        text: "Restaurar aparência padrão"
                        icon.name: "edit-reset"
                        onClicked: {
                            win.draft.appearance = JSON.parse(JSON.stringify(Config.defaults().appearance))
                            win.changed()
                        }
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
                readonly property string report: "TrackpMenu " + info.version
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
                            text: "TrackpMenu"
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
}
