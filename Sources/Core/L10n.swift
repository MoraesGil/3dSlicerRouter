import Foundation

/// Textos da interface: português quando o sistema está em pt, inglês nos demais.
public enum L10n {
    static let pt = Locale.preferredLanguages.first?.hasPrefix("pt") ?? false
    static func t(_ pt: String, _ en: String) -> String { Self.pt ? pt : en }

    public static var noPrinter: String { t("Impressora não declarada", "No printer declared") }
    public static var notDeclared: String { t("não declarada", "not declared") }
    public static func plates(_ n: Int) -> String {
        n == 1 ? t("1 mesa", "1 plate") : t("\(n) mesas", "\(n) plates")
    }

    public static func openWhich(_ file: String) -> String { t("Abrir \(file) em qual app?", "Open \(file) with which app?") }
    public static func reasonManual(_ model: String) -> String {
        t("Escolha manual (⌥). Impressora no arquivo: \(model).", "Manual choice (⌥). Printer in the file: \(model).")
    }
    public static func reasonUnknown(_ model: String) -> String {
        t("A impressora \"\(model)\" ainda não tem app definido.", "Printer \"\(model)\" has no app assigned yet.")
    }
    public static func reasonChanged(_ from: String, _ to: String) -> String {
        t("A impressora do arquivo mudou de \(from) para \(to).", "The file's printer changed from \(from) to \(to).")
    }
    public static var reasonNoPrinter: String {
        t("O arquivo não declara impressora e a classificação não teve certeza.",
          "The file declares no printer and the classifier was not confident.")
    }
    public static var otherApp: String { t("Outro app…", "Other app…") }
    public static var cancel: String { t("Cancelar", "Cancel") }
    public static func rememberFor(_ model: String) -> String {
        t("Usar sempre para impressoras \(model)", "Always use for \(model) printers")
    }
    public static var pickTitle: String { t("Escolha o app para abrir o 3MF", "Choose the app to open the 3MF") }
    public static func notFound(_ app: String) -> String { t("\(app) não foi encontrado", "\(app) was not found") }
    public static func openFailed(_ app: String) -> String { t("Não consegui abrir no \(app)", "Could not open in \(app)") }
    public static func about(current: String) -> String {
        t("""
        Abre cada .3mf no fatiador da impressora declarada (Bambu Studio ou Snapmaker Orca).
        Segure ⌥ ao abrir para escolher o app.

        App padrão de .3mf agora: \(current)
        """, """
        Opens every .3mf in the slicer of the printer it was made for (Bambu Studio or Snapmaker Orca).
        Hold ⌥ while opening to pick the app.

        Current default app for .3mf: \(current)
        """)
    }
    public static var makeDefault: String { t("Tornar padrão para .3mf", "Make default for .3mf") }
    public static var close: String { t("Fechar", "Close") }
    public static var defaultFailed: String { t("Não consegui tornar padrão", "Could not set as default") }
    public static var none: String { t("nenhum", "none") }
}
