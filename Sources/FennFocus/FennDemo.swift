import Foundation

/// Screenshot mode: launched with `-FennDemo YES`, Fenn shows a believable workweek of a product lead
/// ("Mara", agency in Hamburg, Q4 pitch for a client called Nordlicht). Everything goes to a separate demo folder,
/// so the real one stays untouched. Tasks, routines and meetings bring their own demo data (`TaskDemo`, `HabitDemo`,
/// `WorkCalendar`, `DayPlanner`); this fills the folder with profile, goals, journal and notes.
enum FennDemo {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "FennDemo") }

    static let person = "Mara"

    /// "Now" for time-of-day UI in screenshots and screen recordings: always a fresh morning (08:40) in demo mode.
    static var now: Date { isOn ? date(0, 8, 40) : Date() }

    static func date(_ daysAgo: Int, _ hour: Int = 8, _ minute: Int = 0) -> Date {
        let calendar = Calendar.current
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: calendar.startOfDay(for: Date())) ?? Date()
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }

    static func key(_ daysAgo: Int) -> String { FennVault.dayKey(date(daysAgo)) }

    // MARK: Day stats

    /// Four weeks, oldest first: two or three focus blocks on most workdays, a few tasks and routines.
    static func dayRecords() -> [DayRecord] {
        (0..<28).reversed().compactMap { ago in
            let weekday = Calendar.current.component(.weekday, from: date(ago))
            let weekend = weekday == 1 || weekday == 7
            if weekend && ago % 3 != 0 { return nil }
            return DayRecord(
                day: key(ago),
                focusBlocks: ago == 0 ? 1 : (weekend ? 0 : 2 + ago % 2),
                tasksCompleted: ago == 0 ? 2 : (weekend ? 1 : 3 + ago % 3),
                habitsDone: ago == 0 ? 1 : (weekend ? 2 : 3 + ago % 2)
            )
        }
    }

    // MARK: Journal

    static func journal() -> [JournalEntry] {
        var plan = JournalEntry(kind: .planDay, date: date(0, 7, 45))
        plan.answers = [
            JournalAnswer(question: JournalKind.planDay.questions[0], answer: tr("Pitch-Deck für Nordlicht fertig machen und das Angebot rausschicken.", "Finish the Nordlicht pitch deck and send the proposal.")),
            JournalAnswer(question: JournalKind.planDay.questions[1], answer: tr("9:30 bis 11:00, nur das Deck – Slack aus.", "9:30 to 11:00, only the deck – Slack off.")),
            JournalAnswer(question: JournalKind.planDay.questions[2], answer: tr("Das Weekly zieht sich – dann kürze ich die Agenda auf drei Punkte.", "The weekly runs long – then I cut the agenda to three points.")),
            JournalAnswer(question: tr("Was ist das eine Ergebnis, das der Fokusblock liefern soll?", "What's the one result the focus block should deliver?"),
                          answer: tr("Die Story-Folien 1–6 stehen.", "Story slides 1–6 are done."), isFollowUp: true)
        ]
        plan.priorities = [tr("Pitch-Deck Nordlicht", "Nordlicht pitch deck"), tr("Angebot schicken", "Send the proposal"), tr("Feedback für Jonas", "Feedback for Jonas")]
        plan.reflection = tr("Klarer Plan. Leg das Deck in den ersten Fokusblock, das Angebot passt in die Lücke nach dem Mittag.",
                             "Clear plan. Put the deck in the first focus block, the proposal fits the gap after lunch.")

        var checkIn = JournalEntry(kind: .checkIn, date: date(0, 7, 30))
        checkIn.scales = [.mood: 4, .energy: 4, .stress: 3, .sleep: 4, .focus: 4]
        checkIn.answers = [JournalAnswer(question: JournalKind.checkIn.questions[0], answer: tr("Der Pitch am Freitag – aber positiv aufgeregt.", "Friday's pitch – but the good kind of nervous.")),
                           JournalAnswer(question: JournalKind.checkIn.questions[1], answer: tr("Zwei Stunden ohne Unterbrechung.", "Two hours without interruptions."))]
        checkIn.reflection = tr("Energie gut: Nutz den Vormittag für das Deck, Meetings erst danach.", "Good energy: use the morning for the deck, meetings after that.")

        var review = JournalEntry(kind: .review, date: date(1, 18, 30))
        review.answers = [
            JournalAnswer(question: JournalKind.review.questions[0], answer: tr("Workshop-Struktur steht, Kunde hat sofort zugesagt.", "Workshop structure is done, the client agreed right away.")),
            JournalAnswer(question: JournalKind.review.questions[1], answer: tr("Zu viele Kontextwechsel am Nachmittag. Morgen Mails nur um 12 und 16 Uhr.", "Too many context switches in the afternoon. Tomorrow emails only at 12 and 4.")),
            JournalAnswer(question: JournalKind.review.questions[2], answer: tr("Jonas, der das Research übernommen hat.", "Jonas, who took over the research."))
        ]
        review.reflection = tr("Starker Tag. Die festen Mail-Fenster sind ein guter Hebel gegen die Kontextwechsel.",
                               "Strong day. Fixed email windows are a good lever against context switching.")

        var goals = JournalEntry(kind: .goals, date: date(9, 19, 0))
        goals.answers = [
            JournalAnswer(question: JournalKind.goals.questions[0], answer: tr("Den Nordlicht-Pitch gewinnen.", "Win the Nordlicht pitch.")),
            JournalAnswer(question: JournalKind.goals.questions[1], answer: tr("Größter Kunde des Jahres, und das Team hat lange darauf hingearbeitet.", "Biggest client of the year, and the team has worked towards it for a long time.")),
            JournalAnswer(question: JournalKind.goals.questions[2], answer: tr("Freitag in zwei Wochen, Zusage per Mail.", "Friday in two weeks, a yes by email.")),
            JournalAnswer(question: JournalKind.goals.questions[3], answer: tr("Jeden Morgen ein Fokusblock aufs Deck.", "One focus block on the deck every morning."))
        ]
        // Three weeks of short check-ins, so patterns (meeting-heavy days vs focus) have something to find.
        var history: [JournalEntry] = []
        for ago in 2...20 where ago % 2 == 0 {
            var entry = JournalEntry(kind: .checkIn, date: date(ago, 7, 40))
            let busy = ago % 6 == 0
            entry.scales = [.mood: busy ? 3 : 4, .energy: 4, .stress: busy ? 4 : 2, .sleep: 4, .focus: busy ? 2 : 4]
            entry.answers = [
                JournalAnswer(question: JournalKind.checkIn.questions[0], answer: busy ? tr("Viele Meetings, wenig Zeit am Stück.", "Lots of meetings, little time in one piece.") : tr("Ruhiger Tag, Zeit fürs Deck.", "Quiet day, time for the deck.")),
                JournalAnswer(question: JournalKind.checkIn.questions[1], answer: busy ? tr("Einen Block ohne Termine.", "One block without meetings.") : tr("Nichts Besonderes.", "Nothing special."))
            ]
            history.append(entry)
        }
        return history + [goals, review, checkIn, plan]
    }

    // MARK: Text files

    static let profile = tr("""
    # Profil
    - Name: Mara, Produktleiterin in einer Agentur in Hamburg
    - Arbeitet am besten vormittags, Meetings lieber ab 13 Uhr
    - Team: Jonas (Research), Lara (Design)
    - Mag kurze, klare Antworten
    """, """
    # Profile
    - Name: Mara, product lead at an agency in Hamburg
    - Works best in the morning, prefers meetings after 1 pm
    - Team: Jonas (research), Lara (design)
    - Likes short, clear answers
    """)

    static let goals = tr("""
    # Ziele

    ## Nordlicht-Pitch gewinnen
    _gesetzt am \(key(9))_

    ## Jeden Morgen ein Fokusblock
    """, """
    # Goals

    ## Win the Nordlicht pitch
    _set on \(key(9))_

    ## One focus block every morning
    """)

    static let insights = [
        tr("Wichtigstes Ziel: den Nordlicht-Pitch gewinnen", "Top goal: win the Nordlicht pitch"),
        tr("Konzentriert sich am besten vormittags", "Focuses best in the morning"),
        tr("Viele Meetings am Stück drücken den Fokus", "Back-to-back meetings hurt focus"),
        tr("Feste Mail-Fenster helfen gegen Kontextwechsel", "Fixed email windows help against context switching")
    ]

    static let coach: [(question: String, answer: String)] = [
        (tr("Ich hab heute nur 90 Minuten ohne Termine – was mache ich zuerst?", "I only have 90 minutes without meetings today – what first?"),
         tr("**Das Pitch-Deck, und nur das:**\n\n1. **Fokusblock 9:30–11:00** – Story-Folien 1–6\n2. **Danach 10 min Pause** – kurz raus\n3. **Angebot** in der Lücke nach dem Mittag\n\n> Slack und Mail bleiben bis 11 zu – ich sperre sie dir, wenn du willst.",
            "**The pitch deck, and only that:**\n\n1. **Focus block 9:30–11:00** – story slides 1–6\n2. **Then a 10 min break** – step outside\n3. **Proposal** in the gap after lunch\n\n> Slack and email stay closed until 11 – I'll block them if you like."))
    ]

    static let notes: [(title: String, body: String)] = [
        (tr("Pitch-Struktur", "Pitch outline"), tr("Mit einem Kundenzitat starten, dann drei Zahlen. Maximal 12 Folien, Demo am Ende.", "Open with a customer quote, then three numbers. Max 12 slides, demo at the end.")),
        (tr("Workshop Nordlicht", "Nordlicht workshop"), tr("Ziele, Zielgruppe, Erfolgsmessung. Lara bringt die Moodboards mit.", "Goals, audience, success metrics. Lara brings the mood boards.")),
        (tr("Ideen fürs Team-Offsite", "Team offsite ideas"), tr("Ein Tag ohne Laptop, Rückblick aufs Jahr, drei Wünsche fürs nächste.", "A day without laptops, look back at the year, three wishes for the next."))
    ]

    /// Fills a demo folder with everything Fenn reads from it.
    static func writeFolder(_ root: URL) {
        FennVault.prepare(root)
        FennVault.writeText(profile, to: FennVault.url(.profile, in: root))
        FennVault.writeText(goals, to: FennVault.url(.goals, in: root))
        let entries = journal()
        for day in Set(entries.map(\.day)) {
            FennVault.writeText(JournalMarkdown.render(entries.filter { $0.day == day }), to: FennVault.url(.journal(day), in: root))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(dayRecords()) { FennVault.write(data, to: FennVault.url(.dayStats, in: root)) }
        for (index, note) in notes.enumerated() {
            let url = FennVault.url(.notesFolder, in: root).appendingPathComponent("\(key(index))-\(note.title.lowercased().replacingOccurrences(of: " ", with: "-")).md")
            FennVault.writeText("# \(note.title)\n\n\(note.body)\n", to: url)
        }
    }
}
