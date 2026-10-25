// =============================================================================
// Overlay.qml — o menu radial
//
// É uma janela transparente que cobre a tela inteira (configurada como
// "layer-shell" no menucontroller.cpp). O anel abre onde está o cursor:
// empurrar o TrackPoint na direção de um item seleciona esse item, e o clique
// esquerdo executa.
//
// Quando o app em foco tem um menu próprio (seção "appMenus" do menu.json), os
// itens dele aparecem num ANEL INTERNO, menor. O anel de fora continua sempre
// igual (o menu geral), para não atrapalhar a memória muscular: empurrão curto
// escolhe um item de dentro, empurrão longo escolhe um de fora.
//
// Dicas rápidas de QML para quem está começando:
//  - "propriedade: valor" define um valor. Se o valor usa outras propriedades,
//    vira um "binding": recalcula sozinho sempre que elas mudam.
//  - "id: nome" dá um nome ao objeto, para outros objetos se referirem a ele.
//  - "onAlgo: ..." roda código quando o sinal "algo" acontece (ex.: onClicked).
//  - Config, Controller e System são os objetos C++ publicados pelo main.cpp.
//  - Ângulos são em radianos (π = 180°). O ângulo 0 aponta para a direita e,
//    como o eixo Y da tela cresce para baixo, ângulos positivos giram no
//    sentido horário. -π/2 aponta para cima.
// =============================================================================

import QtQuick
import QtQuick.Window
import org.kde.kirigami as Kirigami

Window {
    id: root

    visible: false        // quem mostra a janela é o MenuController::show()
    color: "transparent"
    title: "TrackpMenu"

    // ---- Tamanhos e visual (vêm da aba Aparência das configurações) ----
    readonly property var appearance: Config.config.appearance
    readonly property real itemSize: appearance.itemSize
    // "!== false" = ligado, a não ser que o usuário tenha desligado.
    readonly property bool showNumbers: appearance.showNumbers !== false
    readonly property bool showBorder: appearance.showBorder !== false
    // Opacidades vêm em % (0–100) e viram 0–1. O "??" usa o valor da direita
    // quando o da esquerda não existe.
    readonly property real ringOpacity: (appearance.ringOpacity ?? 92) / 100
    readonly property real dimOpacity: (appearance.dimOpacity ?? 18) / 100
    readonly property string blurMode: appearance.blur || "none"
    // Cor do item selecionado: a escolhida pelo usuário ou, se vazia, a do tema.
    readonly property color accent: appearance.accentColor || Kirigami.Theme.highlightColor
    // Formato dos itens: "circle" (círculo), "rounded" (quadrado de cantos
    // arredondados) ou "square" (quadrado com cantos quase retos).
    readonly property real itemRadius: appearance.itemShape === "rounded" ? itemSize * 0.25
                                     : appearance.itemShape === "square" ? 4
                                     : itemSize / 2
    // Duração das animações em ms: "normal", "fast" (metade) ou "off" (0 = sem animação).
    readonly property int animDuration: appearance.animation === "off" ? 0
                                      : appearance.animation === "fast" ? Kirigami.Units.shortDuration / 2
                                      : Kirigami.Units.shortDuration
    readonly property int count: items.length
    // ---- Anel interno (itens do app em foco) ----
    // Só aparece no menu principal: dentro de um submenu fica escondido.
    readonly property var innerItems: stack.length === 0 ? appItems : []
    readonly property int innerCount: innerItems.length
    // Itens de dentro são um pouco menores que os de fora.
    readonly property real innerItemSize: Math.round(itemSize * 0.72)
    // Zona morta: o cursor precisa sair deste círculo em volta do centro para
    // selecionar algo. Evita escolher um item sem querer ao abrir o menu.
    readonly property real innerRadius: itemSize * 0.6
    // Raio do anel interno: logo depois da zona morta (ou maior, se tiver muitos itens).
    readonly property real innerRingRadius: Math.max(innerRadius + innerItemSize / 2 + 8, innerCount * (innerItemSize + 10) / (2 * Math.PI))
    // Com muitos itens o anel cresce, para os círculos nunca se sobreporem:
    // a circunferência (2πr) precisa caber "count" itens com 14 px de folga.
    // Com anel interno, o de fora também se afasta para dar espaço a ele.
    readonly property real ringRadius: Math.max(appearance.radius, count * (itemSize + 14) / (2 * Math.PI),
                                                innerCount ? innerRingRadius + innerItemSize / 2 + itemSize / 2 + 12 : 0)
    // Distância do centro que separa os dois anéis: até aqui, escolhe-se um
    // item de dentro; depois daqui, um de fora.
    readonly property real ringBoundary: (innerRingRadius + ringRadius) / 2
    // Diâmetro do disco de fundo do anel.
    readonly property real discSize: 2 * (ringRadius + itemSize * 0.75)

    // ---- Estado ----
    property var items: []          // itens do nível exibido agora (anel de fora)
    property var appItems: []       // itens do menu do app em foco (anel interno), ou []
    property var stack: []          // níveis anteriores (para voltar de um submenu)
    property var titles: []         // nomes dos submenus abertos, para o texto do centro
    property string rootTitle: ""   // nome do app em foco, se ele tiver menu próprio ("" = não tem)
    // Índice do item selecionado (-1 = nenhum). Os dois anéis são numerados
    // juntos: 0 até count-1 são os de fora, e a partir de count vêm os de dentro.
    property int selected: -1
    // Todos os itens visíveis na mesma ordem do "selected": fora, depois dentro.
    readonly property var allItems: items.concat(innerItems)
    readonly property int totalCount: allItems.length
    // O item selecionado (ou null).
    readonly property var selectedItem: selected >= 0 && selected < totalCount ? allItems[selected] : null
    property bool placed: false     // o anel já foi posicionado na tela?
    property point center           // centro do anel: onde estava o cursor, mas sem sair da tela
    property point lastPos          // última posição conhecida do cursor
    property double shownAt: 0      // quando o menu abriu (em ms), para o "segurar e soltar"
    // Direção do cursor em relação ao centro (usada pela bolinha indicadora).
    readonly property real pointerAngle: Math.atan2(lastPos.y - center.y, lastPos.x - center.x)

    // Pede ao KWin o desfoque atrás do menu. No modo "ring", o desfoque segue
    // o anel, então precisa ser refeito sempre que ele muda de lugar ou tamanho.
    function updateBlur() {
        if (blurMode === "ring" && !placed)
            Controller.setBlur("none", 0, 0, 0)   // anel ainda não apareceu
        else
            Controller.setBlur(blurMode, center.x, center.y, discSize)
    }
    onBlurModeChanged: updateBlur()
    onCenterChanged: updateBlur()
    onDiscSizeChanged: updateBlur()
    onPlacedChanged: updateBlur()

    // Devolve a cor "c" com transparência "a" (0 = invisível, 1 = opaca).
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a)
    }

    // Para itens "liga/desliga": true = ligado, false = desligado,
    // undefined = não existe neste computador (ex.: sem Bluetooth).
    function toggleState(item) {
        return item && item.type === "toggle" ? Toggles.states[item.toggle] : undefined
    }

    // Limita v ao intervalo [lo, hi].
    function clamp(v, lo, hi) {
        return Math.min(Math.max(v, lo), Math.max(lo, hi))
    }

    // Volta ao estado inicial sempre que o menu é aberto.
    function reset() {
        // Pergunta ao C++ qual menu usar: o do app em foco (se houver) ou o geral.
        // O C++ devolve o menu geral (anel de fora) e, se o app em foco tiver
        // um menu próprio, os itens dele (anel interno).
        const menu = Controller.currentMenu()
        items = menu.items
        appItems = menu.appItems
        rootTitle = menu.title
        stack = []
        titles = []
        selected = -1
        placed = false
        shownAt = Date.now()
        Toggles.refresh()   // relê se Wi-Fi, Bluetooth etc. estão ligados
        fallbackTimer.restart()
        keys.forceActiveFocus()
    }

    // Posiciona o anel com o centro em (x, y), empurrando-o para dentro da
    // tela se ele fosse ficar cortado na borda.
    function place(x, y) {
        if (width <= 0 || height <= 0)
            return
        const margin = ringRadius + itemSize
        lastPos = Qt.point(x, y)
        selected = -1
        center = Qt.point(clamp(x, margin, width - margin), clamp(y, margin, height - margin))
        placed = true
    }

    // Ângulo do centro da fatia do item "index" num anel com "n" itens. O item
    // 0 fica no topo (-π/2) e os seguintes vêm em sentido horário.
    function sectorCenter(index, n) {
        return -Math.PI / 2 + index * 2 * Math.PI / n
    }

    // Menor diferença entre dois ângulos (de 0 a π), considerando que o círculo
    // "dá a volta": a distância entre 350° e 10° é 20°, e não 340°.
    function angleDiff(a, b) {
        const d = Math.abs(a - b) % (2 * Math.PI)
        return d > Math.PI ? 2 * Math.PI - d : d
    }

    // Descobre qual item está na direção do cursor. A seleção segue a direção a
    // partir do centro do anel, ou seja, o que o usuário vê na tela.
    // Com dois anéis, a DISTÂNCIA do centro diz qual anel e a DIREÇÃO diz qual item.
    function indexForPointer(x, y) {
        const dx = x - center.x
        const dy = y - center.y
        const dist = Math.hypot(dx, dy)
        // Menu vazio, ou cursor ainda dentro da zona morta: nada selecionado.
        if (totalCount === 0 || dist < innerRadius)
            return -1
        // Qual anel? Também com uma folga (8 px) a favor do anel atual, para a
        // seleção não ficar pulando de um anel para o outro na divisa.
        let inner = false
        if (innerCount > 0) {
            const slack = selected < 0 ? 0 : selected >= count ? 8 : -8
            inner = count === 0 || dist < ringBoundary + slack
        }
        // "n" itens neste anel; "offset" converte a posição no anel para o
        // índice geral (os de dentro começam em "count").
        const n = inner ? innerCount : count
        const offset = inner ? count : 0
        const angle = Math.atan2(dy, dx)
        const sector = 2 * Math.PI / n   // tamanho de cada fatia
        // "Histerese": um ângulo extra que o item selecionado ganha além da sua
        // fatia. Assim, a tremidinha natural do TrackPoint perto da divisa entre
        // dois itens não fica alternando a seleção entre eles.
        // No máximo 10°, ou 30% de meia fatia quando há muitos itens.
        const hysteresis = Math.min(10 * Math.PI / 180, Math.PI / n * 0.3)
        // Se o cursor ainda está na fatia do item atual (mais a histerese), mantém.
        const local = selected - offset
        if (local >= 0 && local < n && angleDiff(angle, sectorCenter(local, n)) <= sector / 2 + hysteresis)
            return selected
        // Converte o ângulo para "quantas fatias a partir do topo": soma π/2 para
        // o topo virar zero e meia fatia para o item 0 ficar centrado no topo.
        let a = angle + Math.PI / 2 + sector / 2
        // Normaliza para o intervalo [0, 2π) (o % do JavaScript pode dar negativo).
        a = ((a % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)
        return offset + Math.floor(a / sector) % n
    }

    // Executa o item "index": entra no submenu ou manda o C++ rodar a ação.
    function trigger(index) {
        if (index < 0 || index >= totalCount)
            return
        const item = allItems[index]
        // "menu" e "windows" abrem um submenu. O de "windows" é montado na hora
        // pelo C++, com as janelas abertas agora.
        if (isSubmenu(item)) {
            // Guarda o nível atual na pilha e mostra os itens do submenu.
            // concat cria uma lista nova; mudar a lista no lugar não avisaria
            // os bindings de que ela mudou.
            stack = stack.concat([items])
            titles = titles.concat([item.label])
            items = item.type === "windows" ? Controller.openWindows() : (item.items || [])
            place(lastPos.x, lastPos.y)
            return
        }
        Controller.activate(item)
    }

    // O item abre um submenu? ("menu" normal ou "windows", montado na hora)
    function isSubmenu(item) {
        return item !== null && (item.type === "menu" || item.type === "windows")
    }

    // Volta um nível. Se já estiver no menu principal, fecha o menu.
    function back() {
        if (stack.length === 0) {
            Controller.hide()
            return
        }
        const s = stack.slice()   // cópia, pelo mesmo motivo do concat acima
        items = s.pop()
        stack = s
        titles = titles.slice(0, -1)
        place(lastPos.x, lastPos.y)
    }

    // Escuta os sinais do Controller (C++). showRequested é emitido logo antes de
    // a janela aparecer.
    Connections {
        target: Controller
        function onShowRequested() { root.reset() }
    }

    // O anel é posicionado no primeiro movimento do cursor. Se o compositor não
    // informar onde está o cursor em 150 ms, abre no meio da tela.
    Timer {
        id: fallbackTimer
        interval: 150
        onTriggered: if (!root.placed) root.place(root.width / 2, root.height / 2)
    }

    // Leve escurecimento da tela inteira atrás do menu, com animação ao aparecer.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, root.dimOpacity)
        opacity: root.placed ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: root.animDuration } }
    }

    // Área que recebe o mouse/TrackPoint na tela inteira.
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true    // recebe movimentos mesmo sem botão apertado
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Quando o cursor "entra" na janela, já sabemos onde ele está.
        onEntered: if (!root.placed) root.place(mouseX, mouseY)
        onPositionChanged: mouse => {
            if (!root.placed) {
                root.place(mouse.x, mouse.y)
                return
            }
            root.lastPos = Qt.point(mouse.x, mouse.y)
            root.selected = root.indexForPointer(mouse.x, mouse.y)
        }
        // Clique sem nada selecionado (cursor no centro): volta/fecha.
        // Botão esquerdo com item selecionado: executa (ou abre, se for submenu).
        // Botão direito com um submenu apontado: abre o submenu. Assim dá para
        // entrar em "Janelas" sem soltar o atalho e escolher a janela soltando.
        // Botão direito apontando um item comum não faz nada.
        onClicked: mouse => {
            if (root.selected < 0)
                root.back()
            else if (mouse.button === Qt.LeftButton || root.isSubmenu(root.selectedItem))
                root.trigger(root.selected)
        }
        // A roda do mouse (ou a rolagem do TrackPoint) gira a seleção.
        onWheel: wheel => {
            if (root.totalCount === 0)
                return
            const step = wheel.angleDelta.y > 0 ? -1 : 1
            root.selected = ((root.selected < 0 ? 0 : root.selected + step) + root.totalCount) % root.totalCount
        }
    }

    // Item invisível que só recebe o teclado.
    Item {
        id: keys
        focus: true
        // "Segurar e soltar": o KDE não avisa direito quando o atalho é solto
        // (manda o "soltou" logo depois do "apertou"). Mas esta janela recebe o
        // soltar da tecla modificadora (Meta, Ctrl, Alt ou Shift) do atalho.
        // Se ela for solta depois de 250 ms com um item apontado, executa o item.
        // Soltar mais rápido que isso é um toque normal: o menu fica aberto
        // esperando o clique. Sem item apontado, o menu também fica aberto.
        // Teclas como Fn+F12 não servem: o notebook manda apertar e soltar juntos.
        Keys.onReleased: event => {
            const modifierKeys = [Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Shift]
            const holdEnabled = !Config.config.behavior || Config.config.behavior.holdToSelect !== false
            if (holdEnabled && !event.isAutoRepeat && modifierKeys.includes(event.key)
                    && Date.now() - root.shownAt >= 250 && root.selected >= 0)
                root.trigger(root.selected)
        }
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                Controller.hide()
            } else if (event.key === Qt.Key_Backspace) {
                root.back()
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                if (root.selected >= 0) root.trigger(root.selected)
            } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down || event.key === Qt.Key_Tab) {
                // Próximo item (o % faz voltar ao primeiro depois do último).
                if (root.totalCount) root.selected = (root.selected + 1) % root.totalCount
            } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up || event.key === Qt.Key_Backtab) {
                // Item anterior (somar count evita índice negativo).
                if (root.totalCount) root.selected = ((root.selected < 0 ? 0 : root.selected) - 1 + root.totalCount) % root.totalCount
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                // Teclas 1–9 executam o item correspondente do anel de fora.
                const index = event.key - Qt.Key_1
                if (index < root.count) root.trigger(index)
            } else {
                return   // tecla que não usamos: deixa passar
            }
            event.accepted = true
        }
    }

    // O anel. Este Item fica exatamente no centro, então dentro dele a
    // coordenada (0, 0) é o centro do anel, o que simplifica as contas.
    Item {
        id: ring
        x: root.center.x
        y: root.center.y
        // Animação de entrada: aparece crescendo um pouco (OutBack = "quica" no fim).
        opacity: root.placed ? 1 : 0
        scale: root.placed ? 1 : 0.8
        Behavior on opacity { NumberAnimation { duration: root.animDuration } }
        Behavior on scale { NumberAnimation { duration: root.animDuration; easing.type: Easing.OutBack } }

        // Usa as cores do tema do KDE para "áreas de conteúdo" (claro/escuro conforme o tema).
        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        // Disco de fundo do anel. radius = metade do tamanho deixa o retângulo redondo.
        Rectangle {
            x: -root.discSize / 2
            y: -root.discSize / 2
            width: root.discSize
            height: root.discSize
            radius: root.discSize / 2
            color: root.alpha(Kirigami.Theme.backgroundColor, root.ringOpacity)
            border.color: root.alpha(Kirigami.Theme.textColor, 0.15)
            border.width: root.showBorder ? 1 : 0
        }

        // Fundo levemente diferente atrás do anel interno, para separar os
        // itens do app dos itens gerais.
        Rectangle {
            visible: root.innerCount > 0
            readonly property real size: 2 * (root.innerRingRadius + root.innerItemSize / 2 + 6)
            x: -size / 2
            y: -size / 2
            width: size
            height: size
            radius: size / 2
            color: root.alpha(Kirigami.Theme.textColor, 0.05)
            border.color: root.alpha(Kirigami.Theme.textColor, 0.12)
            border.width: root.showBorder ? 1 : 0
        }

        // Bolinha que mostra para onde o cursor está apontando.
        // cos/sen do ângulo dão a posição num círculo de raio "dist".
        Rectangle {
            visible: root.selected >= 0
            // Com anel interno, a bolinha fica mais perto do centro, antes dos itens de dentro.
            readonly property real dist: root.innerCount ? root.innerRingRadius - root.innerItemSize / 2 - 6 : root.itemSize * 0.75
            width: 10
            height: 10
            radius: 5
            color: root.accent
            x: Math.cos(root.pointerAngle) * dist - width / 2
            y: Math.sin(root.pointerAngle) * dist - height / 2
        }

        // Centro do anel: nome do item selecionado ou, sem seleção, um ícone de
        // voltar/fechar e o título do menu atual.
        Column {
            x: -width / 2
            y: -height / 2
            spacing: Kirigami.Units.smallSpacing
            // Com anel interno, o texto precisa caber no espaço que sobra dentro dele.
            width: root.innerCount ? 2 * (root.innerRingRadius - root.innerItemSize / 2) - 16 : root.itemSize * 1.3

            Kirigami.Icon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: Kirigami.Units.iconSizes.smallMedium
                height: width
                visible: root.selected < 0
                source: root.stack.length ? "go-previous" : "window-close"
                opacity: 0.6
            }
            Text {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                color: Kirigami.Theme.textColor
                font.weight: root.selected >= 0 ? Font.DemiBold : Font.Normal
                // Encadeamento de "condição ? valor : senão":
                // item selecionado → nome dele; dentro de submenu → nome do submenu;
                // senão → nome do app (se houver anel interno) ou "TrackpMenu"
                // (ou "Menu vazio" se não houver itens).
                text: root.selectedItem ? root.selectedItem.label
                    : root.stack.length ? root.titles[root.titles.length - 1]
                    : root.totalCount ? (root.innerCount ? root.rootTitle : "TrackpMenu") : "Menu vazio"
            }
            // Embaixo do nome de um item liga/desliga, diz o estado atual.
            Text {
                readonly property var state: root.toggleState(root.selectedItem)
                visible: root.selectedItem !== null && root.selectedItem.type === "toggle"
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                font.pointSize: Kirigami.Theme.smallFont.pointSize
                color: root.alpha(Kirigami.Theme.textColor, 0.7)
                text: state === undefined ? "Indisponível" : state ? "Ligado" : "Desligado"
            }
        }

        // Anel de fora: o menu geral (ou o submenu aberto).
        // Repeater cria um RingItem (componente definido no fim do arquivo) para
        // cada item da lista.
        Repeater {
            model: root.items
            delegate: RingItem {
                overlay: root
                ringCount: root.count
                ringDistance: root.ringRadius
            }
        }

        // Anel interno: os itens do app em foco (vazio se ele não tiver menu).
        Repeater {
            model: root.innerItems
            delegate: RingItem {
                overlay: root
                ringCount: root.innerCount
                ringDistance: root.innerRingRadius
                size: root.innerItemSize
                firstIndex: root.count
            }
        }
    }

    // "component" define um tipo novo dentro deste arquivo: o círculo de um item.
    // Os dois anéis usam o mesmo componente, cada um com seus tamanhos.
    component RingItem: Rectangle {
        // "required property" recebe os dados de cada item:
        // modelData = o objeto do item, index = a posição dele na lista.
        required property var modelData
        required property int index
        // Quem usa o componente preenche estes: quantos itens tem o anel, a
        // distância do centro, o tamanho do círculo e onde este anel começa na
        // numeração do "selected" (0 = anel de fora, count = anel interno).
        // Um componente declarado com "component" não enxerga os ids do resto do
        // arquivo (como "root"), então a janela do menu é passada aqui.
        required property var overlay
        property int ringCount: 1
        property real ringDistance: 0
        property real size: overlay ? overlay.itemSize : 0
        property int firstIndex: 0
        readonly property real angle: overlay.sectorCenter(index, ringCount)
        readonly property bool current: firstIndex + index === overlay.selected

        // Posição no anel: cos/sen do ângulo vezes o raio, descontando
        // metade do tamanho para centralizar o círculo nesse ponto.
        x: Math.cos(angle) * ringDistance - width / 2
        y: Math.sin(angle) * ringDistance - height / 2
        width: size
        height: size
        // Mesmo formato (círculo/arredondado/quadrado), na proporção do tamanho.
        radius: overlay.itemRadius * size / overlay.itemSize
        // O selecionado fica com a cor de destaque e um pouco maior.
        color: current ? overlay.accent : Kirigami.Theme.alternateBackgroundColor
        border.color: overlay.alpha(Kirigami.Theme.textColor, current || !overlay.showBorder ? 0 : 0.12)
        scale: current ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: overlay.animDuration } }
        Behavior on color { ColorAnimation { duration: overlay.animDuration } }

        // Ícone do item (nome de ícone do tema do KDE, ex.: "firefox").
        Kirigami.Icon {
            anchors.centerIn: parent
            width: parent.width * 0.55
            height: width
            source: modelData.icon || "application-x-executable"
            selected: parent.current
            // Item liga/desliga que está desligado fica apagadinho.
            opacity: modelData.type === "toggle" && overlay.toggleState(modelData) !== true ? 0.45 : 1
        }

        // Bolinha no canto de itens liga/desliga: verde = ligado,
        // cinza = desligado. O contorno na cor do fundo a destaca do círculo.
        Rectangle {
            visible: modelData.type === "toggle"
            readonly property bool on: overlay.toggleState(modelData) === true
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Math.round(parent.size * 0.26)
            height: width
            radius: width / 2
            color: on ? Kirigami.Theme.positiveTextColor : overlay.alpha(Kirigami.Theme.textColor, 0.35)
            border.color: Kirigami.Theme.backgroundColor
            border.width: 2
        }

        // Setinha no canto indicando que o item abre um submenu.
        Kirigami.Icon {
            visible: overlay.isSubmenu(modelData)
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: Kirigami.Units.iconSizes.small
            height: width
            source: "go-next-symbolic"
            selected: parent.current
        }

        // Número da tecla de atalho (1–9) no canto do círculo (só no anel de fora).
        Text {
            visible: overlay.showNumbers && parent.firstIndex === 0 && index < 9
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.margins: -2
            text: index + 1
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            color: overlay.alpha(Kirigami.Theme.textColor, 0.55)
        }
    }
}
