// =============================================================================
// RingPreview.qml — miniatura do menu radial, usada na aba Aparência
//
// Desenha o anel com as opções de aparência recebidas em "appearance" (as
// mesmas do menu.json), por cima de um "desktop" de mentira. Assim dá para ver
// o efeito de cada opção na hora, sem salvar nem abrir o menu de verdade.
//
// As contas de tamanho são as mesmas do Overlay.qml. O anel é desenhado no
// tamanho real e depois reduzido (scale) para caber no espaço disponível.
//
// Com "interactive: true", passar o mouse num item seleciona ele, para ver a
// cor de destaque e a animação.
// =============================================================================

import QtQuick
import QtQuick.Effects
import org.kde.kirigami as Kirigami

Item {
    id: preview

    // Opções de aparência (formato do menu.json). Quem usa passa uma cópia
    // nova sempre que algo muda, para a prévia se redesenhar.
    property var appearance: ({})
    property bool interactive: true
    // Mostrar o desktop de mentira atrás (as miniaturas dos estilos também usam).
    property bool showWallpaper: true

    // ---- Opções, com os mesmos padrões do resto do app ----
    readonly property real itemSize: appearance.itemSize ?? 64
    readonly property real radius: appearance.radius ?? 120
    readonly property bool showNumbers: appearance.showNumbers !== false
    readonly property bool showBorder: appearance.showBorder !== false
    readonly property real ringOpacity: (appearance.ringOpacity ?? 92) / 100
    readonly property real dimOpacity: (appearance.dimOpacity ?? 18) / 100
    readonly property string blurMode: appearance.blur || "none"
    readonly property color accent: appearance.accentColor || Kirigami.Theme.highlightColor
    readonly property real itemRadius: appearance.itemShape === "rounded" ? itemSize * 0.25
                                     : appearance.itemShape === "square" ? 4
                                     : itemSize / 2
    readonly property int animDuration: appearance.animation === "off" ? 0
                                      : appearance.animation === "fast" ? Kirigami.Units.shortDuration / 2
                                      : Kirigami.Units.shortDuration

    // Itens de exemplo (só ícone e nome).
    readonly property var sampleItems: [
        { label: "Terminal", icon: "utilities-terminal" },
        { label: "Arquivos", icon: "system-file-manager" },
        { label: "Navegador", icon: "internet-web-browser" },
        { label: "Visão geral", icon: "view-app-grid" },
        { label: "Captura", icon: "spectacle" },
        { label: "Mídia", icon: "applications-multimedia" },
        { label: "Ligar/desligar", icon: "preferences-system" },
        { label: "Bloquear", icon: "system-lock-screen" }
    ]
    readonly property int count: sampleItems.length
    // Mesmas fórmulas do Overlay.qml.
    readonly property real ringRadius: Math.max(radius, count * (itemSize + 14) / (2 * Math.PI))
    readonly property real discSize: 2 * (ringRadius + itemSize * 0.75)
    // Quanto o anel precisa encolher para caber (nunca aumenta além do real).
    readonly property real fit: Math.min(1, (Math.min(width, height) - 16) / discSize)

    // Item apontado pelo mouse (-1 = nenhum). Sem mouse, mostra o 1º como selecionado.
    property int hovered: -1
    readonly property int selected: interactive ? hovered : 0

    clip: true

    // ---- "Desktop" de mentira ----
    // Tem formas e cores para o desfoque e o escurecimento ficarem visíveis.
    Item {
        id: wallpaper
        anchors.fill: parent
        visible: preview.showWallpaper

        // Fundo colorido fixo (azul → roxo), parecido com os papéis de parede do KDE.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0; color: "#1d99f3" }
                GradientStop { position: 0.55; color: "#3b4fa8" }
                GradientStop { position: 1; color: "#2a1f4d" }
            }
        }
        // Duas "janelas" de enfeite.
        Repeater {
            model: [
                { x: 0.06, y: 0.08, w: 0.5, h: 0.42 },
                { x: 0.46, y: 0.5, w: 0.48, h: 0.4 }
            ]
            delegate: Rectangle {
                required property var modelData
                x: modelData.x * wallpaper.width
                y: modelData.y * wallpaper.height
                width: modelData.w * wallpaper.width
                height: modelData.h * wallpaper.height
                radius: 6
                color: Kirigami.Theme.backgroundColor
                border.color: Qt.rgba(0, 0, 0, 0.2)
                // Barra de título e algumas "linhas de texto".
                Rectangle { width: parent.width; height: 14; radius: 6; color: Kirigami.Theme.alternateBackgroundColor }
                Column {
                    x: 10; y: 24; spacing: 7
                    Repeater {
                        model: 6
                        Rectangle {
                            required property int index
                            width: (parent.parent.width - 20) * (index % 2 ? 0.6 : 0.85)
                            height: 5; radius: 2
                            color: Qt.rgba(0.5, 0.5, 0.5, 0.35)
                        }
                    }
                }
            }
        }
    }

    // ---- Desfoque ----
    // MultiEffect desenha uma cópia borrada do desktop. No modo "ring", uma
    // máscara redonda deixa o borrado só atrás do anel.
    MultiEffect {
        anchors.fill: parent
        visible: preview.showWallpaper && preview.blurMode !== "none"
        source: wallpaper
        blurEnabled: true
        blur: 1
        blurMax: 40
        // Sem margem extra em volta: assim a máscara cai exatamente sobre o anel.
        autoPaddingEnabled: false
        maskEnabled: preview.blurMode === "ring"
        maskSource: blurMask
    }
    // A máscara: um círculo do tamanho do disco (já reduzido) no centro.
    // layer.enabled transforma o item numa imagem que o MultiEffect consegue usar.
    Item {
        id: blurMask
        anchors.fill: parent
        layer.enabled: true
        visible: false
        Rectangle {
            anchors.centerIn: parent
            width: preview.discSize * preview.fit
            height: width
            radius: width / 2
        }
    }

    // ---- Escurecimento da tela ----
    Rectangle {
        anchors.fill: parent
        visible: preview.showWallpaper
        color: Qt.rgba(0, 0, 0, preview.dimOpacity)
    }

    // ---- O anel ----
    // Desenhado no tamanho real em volta de (0, 0) e reduzido por "fit".
    Item {
        id: ring
        x: preview.width / 2
        y: preview.height / 2
        scale: preview.fit
        transformOrigin: Item.TopLeft

        Kirigami.Theme.colorSet: Kirigami.Theme.View
        Kirigami.Theme.inherit: false

        // Disco de fundo.
        Rectangle {
            x: -preview.discSize / 2
            y: -preview.discSize / 2
            width: preview.discSize
            height: preview.discSize
            radius: preview.discSize / 2
            color: Qt.rgba(Kirigami.Theme.backgroundColor.r, Kirigami.Theme.backgroundColor.g, Kirigami.Theme.backgroundColor.b, preview.ringOpacity)
            border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.15)
            border.width: preview.showBorder ? 1 : 0
        }

        // Nome do item apontado no centro.
        Text {
            anchors.centerIn: parent
            width: preview.itemSize * 1.3
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: Kirigami.Theme.textColor
            font.weight: preview.selected >= 0 ? Font.DemiBold : Font.Normal
            text: preview.selected >= 0 ? preview.sampleItems[preview.selected].label : "KTrackMenu"
        }

        // Os itens, um em cada fatia, a partir do topo, em sentido horário.
        Repeater {
            model: preview.sampleItems
            delegate: Rectangle {
                id: ringItem
                required property var modelData
                required property int index
                readonly property real angle: -Math.PI / 2 + index * 2 * Math.PI / preview.count
                readonly property bool current: index === preview.selected

                x: Math.cos(angle) * preview.ringRadius - width / 2
                y: Math.sin(angle) * preview.ringRadius - height / 2
                width: preview.itemSize
                height: preview.itemSize
                radius: preview.itemRadius
                color: current ? preview.accent : Kirigami.Theme.alternateBackgroundColor
                border.color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b,
                                      current || !preview.showBorder ? 0 : 0.12)
                scale: current ? 1.12 : 1
                Behavior on scale { NumberAnimation { duration: preview.animDuration } }
                Behavior on color { ColorAnimation { duration: preview.animDuration } }

                Kirigami.Icon {
                    anchors.centerIn: parent
                    width: parent.width * 0.55
                    height: width
                    source: ringItem.modelData.icon
                    selected: ringItem.current
                }

                Text {
                    visible: preview.showNumbers
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: -2
                    text: ringItem.index + 1
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    color: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.55)
                }

                // Passar o mouse seleciona o item (só na prévia grande).
                HoverHandler {
                    enabled: preview.interactive
                    onHoveredChanged: {
                        if (hovered) preview.hovered = ringItem.index
                        else if (preview.hovered === ringItem.index) preview.hovered = -1
                    }
                }
            }
        }
    }
}
