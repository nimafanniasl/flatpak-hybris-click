import QtQuick 2.12
import Lomiri.Components 1.3

MainView {
    id: root
    objectName: "mainView"
    applicationName: "flatpak-hybris.ubports"
    width: units.gu(45)
    height: units.gu(75)

    property var status: ({})

    function statusPath() {
        var args = Qt.application.arguments
        for (var i = 0; i < args.length; i++)
            if (args[i].indexOf("status.json") !== -1)
                return args[i]
        return ""
    }

    Component.onCompleted: {
        var path = statusPath()
        if (path === "")
            return
        var xhr = new XMLHttpRequest()
        xhr.onreadystatechange = function () {
            if (xhr.readyState === XMLHttpRequest.DONE) {
                try {
                    root.status = JSON.parse(xhr.responseText)
                } catch (e) {
                    root.status = {}
                }
            }
        }
        xhr.open("GET", "file://" + path)
        xhr.send()
    }

    Page {
        anchors.fill: parent
        header: PageHeader {
            id: header
            title: i18n.tr("Flatpak (hybris)")
        }

        Flickable {
            anchors {
                top: header.bottom
                left: parent.left
                right: parent.right
                bottom: parent.bottom
                margins: units.gu(2)
            }
            contentHeight: col.height
            clip: true

            Column {
                id: col
                width: parent.width
                spacing: units.gu(2)

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textSize: Label.Large
                    text: status.flatpakVersion
                          ? i18n.tr("Flatpak %1 is set up").arg(status.flatpakVersion)
                          : i18n.tr("Flatpak status unavailable")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    color: status.bwrapOk ? theme.palette.normal.positive
                                          : theme.palette.normal.negative
                    text: status.bwrapOk
                          ? i18n.tr("Sandbox: working (%1)").arg(status.bwrapMsg || "")
                          : i18n.tr("Sandbox: NOT working. The kernel likely lacks unprivileged user namespaces (CONFIG_USER_NS). %1").arg(status.bwrapMsg || "")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: status.flathubOk
                          ? i18n.tr("Flathub remote: configured (per-user)")
                          : i18n.tr("Flathub remote: not configured (no network?). Relaunch to retry.")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: (status.runtimes || "").trim().length > 0
                    text: i18n.tr("Runtimes: %1").arg(status.runtimes || "")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    visible: (status.apps || "").trim().length > 0
                    text: i18n.tr("Apps: %1").arg(status.apps || "")
                }

                Rectangle {
                    width: parent.width
                    height: units.dp(1)
                    color: theme.palette.normal.base
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    text: i18n.tr("Use flatpak from the Terminal app:")
                }

                Label {
                    width: parent.width
                    wrapMode: Text.WrapAnywhere
                    font.family: "Ubuntu Mono"
                    textSize: Label.Small
                    text: "flatpak install flathub org.gnome.Calculator\n" +
                          "flatpak run org.gnome.Calculator"
                }

                Label {
                    width: parent.width
                    wrapMode: Text.Wrap
                    textSize: Label.Small
                    text: i18n.tr("A 'flatpak' symlink was placed in ~/.local/bin (log out and back in once if it is not found). GL goes through the bundled libhybris extension; installs are per-user under ~/.local/share/flatpak.")
                }
            }
        }
    }
}
