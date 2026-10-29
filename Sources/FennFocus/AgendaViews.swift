import SwiftUI

/// Today on the Mac starts with work: the next meeting (with a join button), what's left of the day
/// and the longest free stretch as a focus block.
struct AgendaCard: View {
    @ObservedObject var calendar: WorkCalendar
    let startFocus: (_ until: Date) -> Void
    let openConnections: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("DEIN TAG", "YOUR DAY")).font(.fenn(size: 11, weight: .medium)).tracking(1.2).foregroundStyle(Fenn.fg.opacity(0.55))
            if !calendar.enabled {
                Button(action: openConnections) {
                    FennRow(title: tr("Kalender verbinden", "Connect calendar"),
                            subtitle: tr("Termine und freie Zeit auf einen Blick", "Meetings and free time at a glance"),
                            symbol: "calendar.badge.plus")
                }
                .buttonStyle(.plain)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    content(now: context.date)
                }
            }
        }
        .task(id: calendar.enabled) { await calendar.refresh() }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        let today = calendar.events(on: now).filter { !$0.isAllDay && $0.end > now }
        let focus = FreeTime.focusWindow(busy: calendar.busy(on: now), workHours: calendar.workStart..<calendar.workEnd, now: now)
        meetings(today, focus: focus, now: now)
    }

    @ViewBuilder
    private func meetings(_ today: [AgendaEvent], focus: DateInterval?, now: Date) -> some View {
        if let next = today.first {
            nextMeeting(next, now: now)
        } else if calendar.accessDenied && calendar.feeds.isEmpty {
            Text(tr("Kein Kalenderzugriff – Systemeinstellungen › Datenschutz › Kalender.", "No calendar access – System Settings › Privacy › Calendars."))
                .font(.fenn(size: 12)).foregroundStyle(Fenn.danger)
        } else {
            Text(tr("Heute keine Termine mehr.", "No more meetings today."))
                .font(.fenn(size: 13, weight: .light)).foregroundStyle(Fenn.fg.opacity(0.7))
        }

        if today.count > 1 {
            VStack(spacing: 0) {
                ForEach(today.dropFirst().prefix(2)) { event in
                    HStack(spacing: 12) {
                        DotMatrixText(text: Self.time(event.start), height: 11, color: Fenn.fg.opacity(0.8), glow: false)
                            .frame(width: 50, alignment: .leading)
                        Text(event.title).font(.fenn(size: 13)).foregroundStyle(Fenn.fg).lineLimit(1)
                        Spacer()
                        if let url = event.joinURL { Link(destination: url) { Image(systemName: "video").font(.fenn(size: 11)) }.foregroundStyle(Fenn.accent) }
                    }
                    .padding(.vertical, 7)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .fennGlass(cornerRadius: 18, shadow: false)
        }

        if let focus {
            let minutes = Int(focus.duration / 60)
            Button { startFocus(focus.end) } label: {
                FennRow(title: tr("Fokuszeit \(Self.time(focus.start))–\(Self.time(focus.end))", "Focus time \(Self.time(focus.start))–\(Self.time(focus.end))"),
                        subtitle: tr("\(minutes) min frei", "\(minutes) min free"),
                        symbol: "scope")
            }
            .buttonStyle(.plain)
        }

    }

    private func nextMeeting(_ event: AgendaEvent, now: Date) -> some View {
        let running = event.start <= now
        let minutes = Int(event.start.timeIntervalSince(now) / 60)
        return HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(running ? tr("LÄUFT GERADE", "IN PROGRESS") : minutes < 60 ? tr("IN \(minutes) MIN", "IN \(minutes) MIN") : tr("ALS NÄCHSTES", "NEXT"))
                    .font(.fenn(size: 10, weight: .semibold)).tracking(1.1).foregroundStyle(MeshAura.Palette.steady.ink.opacity(0.85))
                Text(event.title).font(.fenn(size: 16, weight: .regular)).foregroundStyle(MeshAura.Palette.steady.ink).lineLimit(2)
                Text(Self.time(event.start) + "–" + Self.time(event.end) + ", " + event.calendar)
                    .font(.fenn(size: 11, weight: .light)).foregroundStyle(MeshAura.Palette.steady.ink.opacity(0.8))
            }
            Spacer()
            if let url = event.joinURL {
                Link(destination: url) {
                    Label(tr("Beitreten", "Join"), systemImage: "video.fill").font(.fenn(size: 12, weight: .medium))
                        .foregroundStyle(Color(white: 0.12)).padding(.horizontal, 12).frame(height: 30).background(Capsule().fill(Color.white))
                }
                .buttonStyle(.plain)
            } else {
                DotMatrixText(text: Self.time(event.start), height: 20, color: MeshAura.Palette.steady.ink)
            }
        }
        .padding(16)
        .background(ZStack { MeshAura(palette: .steady); LinearGradient(colors: [.white.opacity(0.18), .clear, .black.opacity(0.15)], startPoint: .top, endPoint: .bottom) }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.08)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func time(_ date: Date) -> String { clock.string(from: date) }

    static func day(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return tr("Heute", "Today") }
        if Calendar.current.isDateInTomorrow(date) { return tr("Morgen", "Tomorrow") }
        return date.formatted(.dateTime.weekday(.abbreviated).locale(fennLocale))
    }
}

/// Connections › Calendar: optional, with a short guide per provider.
struct CalendarSettingsCard: View {
    @ObservedObject var calendar: WorkCalendar
    @State private var feedName = ""
    @State private var feedURL = ""
    @State private var showsCalendars = false
    @State private var showsHowTo = false
    @State private var asksCleanup = false
    @State private var cleanupMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.fenn(size: 15)).foregroundStyle(Fenn.accent)
                    .frame(width: 34, height: 34).background(Circle().fill(Fenn.accent.opacity(0.14)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(tr("Kalender", "Calendar")).font(.fenn(size: 14))
                    Text(status).font(.fenn(size: 12)).foregroundStyle(Fenn.fg.opacity(0.6))
                }
                Spacer()
                Toggle("", isOn: Binding(get: { calendar.enabled }, set: { on in
                    if on { Task { await calendar.enable() } } else { calendar.disable() }
                }))
                    .toggleStyle(.switch).labelsHidden().tint(Fenn.accent)
            }

            if calendar.enabled {
                if calendar.accessDenied {
                    HStack {
                        Text(tr("Kein Zugriff auf Kalender.", "No calendar access.")).font(.fenn(size: 12)).foregroundStyle(Fenn.danger)
                        Button(tr("Datenschutz öffnen", "Open Privacy")) { WorkCalendar.openCalendarPrivacy() }.buttonStyle(.link)
                    }
                }
                if !calendar.calendars.isEmpty {
                    DisclosureGroup(isExpanded: $showsCalendars) {
                        ForEach(calendar.calendars) { item in
                            Toggle(isOn: Binding(get: { !calendar.excluded.contains(item.id) }, set: { on in
                                if on { calendar.excluded.remove(item.id) } else { calendar.excluded.insert(item.id) }
                            })) {
                                Text("\(item.title), \(item.account)").font(.fenn(size: 12))
                            }
                            .toggleStyle(.checkbox)
                        }
                    } label: {
                        Text(tr("Kalender, die als belegt zählen", "Calendars that count as busy")).font(.fenn(size: 12, weight: .medium))
                    }
                }

                ForEach(calendar.feeds) { feed in
                    HStack {
                        ClaySymbol(symbol: "link", size: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feed.name).font(.fenn(size: 12))
                            if let error = calendar.feedErrors[feed.id] { Text(error).font(.fenn(size: 11)).foregroundStyle(Fenn.danger) }
                        }
                        Spacer()
                        Button { calendar.feeds.removeAll { $0.id == feed.id }; Task { await calendar.refresh() } } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.plain).foregroundStyle(Fenn.fg.opacity(0.5))
                    }
                }

                HStack {
                    Stepper(tr("Arbeit ab \(calendar.workStart):00", "Work from \(calendar.workStart):00"), value: $calendar.workStart, in: 5...12)
                    Stepper(tr("bis \(calendar.workEnd):00", "until \(calendar.workEnd):00"), value: $calendar.workEnd, in: 13...22)
                }
                .font(.fenn(size: 12))
            }

            // Everything Fenn wrote, out again.
            if FennCalendarCleanup.hasAccess {
                HStack(spacing: 10) {
                    Button(tr("Alle Fenn-Termine entfernen", "Remove all Fenn events"), role: .destructive) { asksCleanup = true }
                        .buttonStyle(FennPillButtonStyle())
                    if let cleanupMessage {
                        Text(cleanupMessage).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.6))
                    }
                }
                .confirmationDialog(tr("Alle Fenn-Termine entfernen?", "Remove all Fenn events?"), isPresented: $asksCleanup) {
                    Button(tr("Entfernen", "Remove"), role: .destructive) {
                        do { cleanupMessage = FennCalendarCleanup.summary(try FennCalendarCleanup.removeAll()) } catch { cleanupMessage = error.localizedDescription }
                    }
                } message: {
                    Text(tr("Aufgaben verschwinden aus dem Apple Kalender, das Eintragen wird auf diesem Mac ausgeschaltet. Deine Aufgaben bleiben.",
                            "Tasks leave Apple Calendar and adding them is switched off on this Mac. Your tasks stay."))
                }
            }

            // Where calendars come from – only needed once, so it folds away.
            DisclosureGroup(isExpanded: $showsHowTo) {
                VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    provider("iCloud", tr("Ist schon da, wenn du am Mac mit deiner Apple-ID angemeldet bist.", "Already there when you're signed in with your Apple ID."))
                    provider("Google Calendar", tr("Systemeinstellungen › Internetaccounts › Google, Kalender einschalten.", "System Settings › Internet Accounts › Google, turn on Calendars."))
                    provider("Outlook, Teams", tr("Internetaccounts › Microsoft Exchange mit der Arbeitsadresse. Teams-Meetings stehen im Outlook-Kalender und bekommen „Beitreten“.",
                                                  "Internet Accounts › Microsoft Exchange with your work address. Teams meetings live in the Outlook calendar and get “Join”."))
                    provider(tr("ICS-Link", "ICS link"), tr("Z. B. Outlook „Kalender veröffentlichen“ oder Google „Privatadresse im iCal-Format“ – unten einfügen.",
                                                             "E.g. Outlook “Publish calendar” or Google “Secret address in iCal format” – paste below."))
                    Button(tr("Internetaccounts öffnen", "Open Internet Accounts")) { WorkCalendar.openInternetAccounts() }
                        .buttonStyle(FennPillButtonStyle())
                }
                    if calendar.enabled {
                    HStack(spacing: 6) {
                        TextField(tr("Name", "Name"), text: $feedName).textFieldStyle(.roundedBorder).frame(width: 90)
                        TextField(tr("ICS-Link (https:// oder webcal://)", "ICS link (https:// or webcal://)"), text: $feedURL).textFieldStyle(.roundedBorder)
                        Button(tr("Hinzufügen", "Add")) {
                            calendar.feeds.append(ICSFeed(name: feedName.isEmpty ? tr("Kalender", "Calendar") : feedName, url: feedURL.trimmingCharacters(in: .whitespaces)))
                            feedName = ""; feedURL = ""
                            Task { await calendar.refresh() }
                        }
                        .disabled(feedURL.isEmpty)
                    }
                    }
                }
                .padding(.top, 6)
            } label: {
                Text(tr("Kalender hinzufügen", "Add calendars")).font(.fenn(size: 12, weight: .medium))
            }

            Text(tr("Termine bleiben auf diesem Mac – nichts geht an ein KI-Modell.", "Events stay on this Mac – nothing goes to an AI model."))
                .font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.5))
                .help(tr("Fenn liest die Termine nur auf diesem Mac, um freie Zeit zu finden – nichts davon geht an ein KI-Modell oder einen Server. ICS-Links ruft Fenn direkt beim Anbieter ab.",
                         "Fenn reads events only on this Mac to find free time – none of it goes to an AI model or a server. ICS links are fetched directly from the provider."))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Fenn.fill))
    }

    private var status: String {
        guard calendar.enabled else { return tr("Aus", "Off") }
        let count = calendar.calendars.filter { !calendar.excluded.contains($0.id) }.count + calendar.feeds.count
        return tr("\(count) Kalender", "\(count) calendars")
    }

    private func provider(_ name: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(.fenn(size: 12, weight: .medium)).foregroundStyle(Fenn.fg).frame(width: 104, alignment: .leading)
            Text(detail).font(.fenn(size: 11)).foregroundStyle(Fenn.fg.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
        }
    }
}
