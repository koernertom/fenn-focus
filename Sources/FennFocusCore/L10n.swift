import Foundation

/// Minimal DE+EN copy shared by the app and the widgets.
/// Prefers device preferred languages; falls back to German, then English.
public enum L10n {
    public enum Key: String, CaseIterable, Sendable {
        case emptyPlanTitle
        case emptyPlanMessage
        case errorPlanTitle
        case errorPlanDetail
        case errorRetry
        case errorLater
        case footerUpdatedOnOpen
        case syncButton
        case syncHint
        case hostSubtitle
        case syncOk
        case sourcePrefix
        case sourceLocal
        case sourceCalendar
        case kindFolder
        case kindTask
        case kindEvent
        case kindNote
        case statusTodo
        case statusDoing
        case statusDone
        case statusBlocked
        case placeholderLoading
        case coachEmptyHint = "coach.empty_hint"
        case coachInputPlaceholder = "coach.input_placeholder"
        case coachSending = "coach.sending"
        case coachErrorMissingKey = "coach.error.missing_key"
        case coachErrorGeneric = "coach.error.generic"
        case coachOpenButton = "coach.open_button"
    }

    private static let table: [Key: (de: String, en: String)] = [
        .emptyPlanTitle: ("Noch kein Plan", "No plan yet"),
        .emptyPlanMessage: (
            "Öffne die App und synchronisiere manuell oder beim Öffnen.",
            "Open the app and sync manually or when opening."
        ),
        .errorPlanTitle: ("Plan konnte nicht geladen werden", "Couldn’t load plan"),
        .errorPlanDetail: (
            "Die lokale Datei ist ungültig oder fehlt. Stichprobe neu schreiben oder später erneut öffnen.",
            "The local file is invalid or missing. Rewrite the sample or try again later."
        ),
        .errorRetry: ("Erneut versuchen", "Try again"),
        .errorLater: ("Später", "Later"),
        .footerUpdatedOnOpen: ("Aktualisiert bei Öffnen", "Updates when opened"),
        .syncButton: ("Sync / Sample schreiben", "Sync / Write sample"),
        .syncHint: (
            "Schreibt Planbaum und persönlichen Fortschritt in die App Group und lädt beide Widgets neu.",
            "Writes the plan tree and personal progress into the App Group and reloads both widgets."
        ),
        .hostSubtitle: (
            "Host-Stub, Planbaum lokal schreiben, Widget neu laden",
            "Host stub, Write plan tree locally, Reload widget"
        ),
        .syncOk: (
            "Plan und Fortschritt geschrieben, Widgets neu geladen",
            "Plan and progress written, Widgets reloaded"
        ),
        .sourcePrefix: ("Quelle: %@", "Source: %@"),
        .sourceLocal: ("Lokal", "Local"),
        .sourceCalendar: ("Kalender", "Calendar"),
        .kindFolder: ("Ordner", "Folder"),
        .kindTask: ("Aufgabe", "Task"),
        .kindEvent: ("Termin", "Event"),
        .kindNote: ("Notiz", "Note"),
        .statusTodo: ("offen", "open"),
        .statusDoing: ("in Arbeit", "in progress"),
        .statusDone: ("erledigt", "done"),
        .statusBlocked: ("blockiert", "blocked"),
        .placeholderLoading: ("Plan wird geladen", "Loading plan"),
        .coachEmptyHint: (
            "Frag Fenn zu Aufgaben, Terminen, Fokus oder deinem Tag.",
            "Ask Fenn about tasks, meetings, focus or your day."
        ),
        .coachInputPlaceholder: ("Frag Fenn …", "Ask Fenn …"),
        .coachSending: ("Fenn denkt nach …", "Fenn is thinking …"),
        .coachErrorMissingKey: ("Kein Claude-Schlüssel hinterlegt – siehe Konnektoren.", "No Claude key saved – see Connectors."),
        .coachErrorGeneric: ("Fenn konnte nicht antworten.", "Fenn couldn’t reply."),
        .coachOpenButton: ("Fenn öffnen", "Open Fenn")
    ]

    /// Resolved language: first preferred that is `de` or `en`, else `de`.
    public static var usesEnglish: Bool {
        let codes = Locale.preferredLanguages.map { String($0.prefix(2)).lowercased() }
        if let match = codes.first(where: { $0 == "en" || $0 == "de" }) {
            return match == "en"
        }
        return false
    }

    public static func string(_ key: Key) -> String {
        guard let pair = table[key] else { return key.rawValue }
        return usesEnglish ? pair.en : pair.de
    }

    public static func string(_ key: Key, _ arg: String) -> String {
        String(format: string(key), locale: usesEnglish ? Locale(identifier: "en") : Locale(identifier: "de"), arg)
    }

    public static func string(_ key: Key, _ arg: Int) -> String {
        String(format: string(key), locale: usesEnglish ? Locale(identifier: "en") : Locale(identifier: "de"), arg)
    }

    public static func sourceLabel(_ raw: String) -> String {
        switch raw {
        case "local": return string(.sourceLocal)
        case "calendar": return string(.sourceCalendar)
        default:
            return raw.hasPrefix("connector:") ? String(raw.dropFirst("connector:".count)) : raw
        }
    }
}
