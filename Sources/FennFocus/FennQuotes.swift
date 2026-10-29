import Foundation

/// The line under the pebble on "Ideen": one per day, classics and Fenn's own sayings taking turns.
/// Only old, freely usable quotes; where the wording is a common paraphrase it says "nach …".
enum FennQuotes {
    struct Quote: Equatable {
        let text: String
        let by: String
    }

    static var today: Quote { quote(for: Date()) }

    static func quote(for date: Date) -> Quote {
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return all[day % all.count]
    }

    private static let fenn = "Fenn"

    static var all: [Quote] {
        [
            Quote(text: tr("Steter Tropfen höhlt den Stein.", "Dripping water hollows out stone."), by: tr("nach Ovid", "after Ovid")),
            Quote(text: tr("Eine Idee muss nicht fertig sein. Nur aufgeschrieben.", "An idea doesn't need to be finished. Just written down."), by: fenn),
            Quote(text: tr("Eine Reise von tausend Meilen beginnt mit dem ersten Schritt.", "A journey of a thousand miles begins with a single step."), by: "Laozi"),
            Quote(text: tr("Was dich dreimal beschäftigt, verdient eine eigene Seite.", "What's on your mind three times deserves its own page."), by: fenn),
            Quote(text: tr("Nicht weil es schwer ist, wagen wir es nicht – weil wir es nicht wagen, ist es schwer.", "It is not because things are difficult that we do not dare; it is because we do not dare that they are difficult."), by: "Seneca"),
            Quote(text: tr("Klein anfangen ist auch anfangen.", "Starting small is still starting."), by: fenn),
            Quote(text: tr("Der Weg entsteht beim Gehen.", "The path is made by walking."), by: tr("nach Antonio Machado", "after Antonio Machado")),
            Quote(text: tr("Die besten Ideen kommen beim Laufen. Sag sie mir, bevor du duschst.", "The best ideas come on a run. Tell me before you shower."), by: fenn),
            Quote(text: tr("Das Hindernis auf dem Weg wird zum Weg.", "What stands in the way becomes the way."), by: tr("nach Marc Aurel", "after Marcus Aurelius")),
            Quote(text: tr("Langsam ist auch eine Richtung.", "Slow is a direction too."), by: fenn),
            Quote(text: tr("Wir haben nicht zu wenig Zeit – wir nutzen zu wenig davon.", "It is not that we have little time, but that we waste much of it."), by: tr("nach Seneca", "after Seneca")),
            Quote(text: tr("Nicht jede Idee muss groß werden. Manche müssen nur raus.", "Not every idea has to grow. Some just need to get out."), by: fenn),
            Quote(text: tr("Auch aus Steinen, die einem in den Weg gelegt werden, kann man Schönes bauen.", "Even stones placed in your way can become something beautiful."), by: tr("Goethe zugeschrieben", "attributed to Goethe")),
            Quote(text: tr("Heute reicht ein Schritt. Morgen kommt der nächste.", "One step is enough today. The next one comes tomorrow."), by: fenn),
            Quote(text: tr("Wer nicht weiß, welchen Hafen er ansteuert, für den ist kein Wind günstig.", "If one does not know to which port one is sailing, no wind is favourable."), by: "Seneca"),
            Quote(text: tr("Eine halbe Idee ist mehr als keine.", "Half an idea is more than none."), by: fenn),
            Quote(text: tr("Wir sind, was wir wiederholt tun.", "We are what we repeatedly do."), by: tr("nach Aristoteles", "after Aristotle")),
            Quote(text: tr("Frag dich nicht, ob es gut ist. Frag dich, ob es weitergeht.", "Don't ask if it's good. Ask if it keeps going."), by: fenn),
            Quote(text: tr("Es ist nicht genug zu wissen, man muss auch anwenden.", "Knowing is not enough; we must apply."), by: "Goethe"),
            Quote(text: tr("Gedanken werden leichter, wenn man sie ablegt.", "Thoughts get lighter once you put them down."), by: fenn),
            Quote(text: tr("Der Anfang ist die Hälfte des Ganzen.", "The beginning is half of the whole."), by: tr("nach Aristoteles", "after Aristotle")),
            Quote(text: tr("Eine Frage weiter ist auch weiter.", "One more question is progress too."), by: fenn),
            Quote(text: tr("Die Zeit ist das Kostbarste, was ein Mensch verwenden kann.", "Time is the most valuable thing a man can spend."), by: tr("nach Theophrast", "after Theophrastus")),
            Quote(text: tr("Gute Ideen dürfen erst mal schlecht klingen.", "Good ideas are allowed to sound bad at first."), by: fenn),
            Quote(text: tr("Nichts ist so beständig wie der Wandel.", "The only constant is change."), by: tr("nach Heraklit", "after Heraclitus")),
            Quote(text: tr("Du musst nicht wissen, wie es endet. Nur, was als Nächstes kommt.", "You don't need to know how it ends. Just what comes next."), by: fenn),
            Quote(text: tr("Übung macht den Meister.", "Practice makes perfect."), by: tr("Sprichwort", "Proverb")),
            Quote(text: tr("Ein Stein liegt still – und rollt doch, wenn man ihn anstößt.", "A stone lies still – and rolls once you nudge it."), by: fenn),
            Quote(text: tr("Glück ist, was passiert, wenn Vorbereitung auf Gelegenheit trifft.", "Luck is what happens when preparation meets opportunity."), by: tr("Seneca zugeschrieben", "attributed to Seneca")),
            Quote(text: tr("Pausen gehören zum Plan. Auch bei Ideen.", "Rest is part of the plan. For ideas too."), by: fenn),
            Quote(text: tr("Wer will, findet Wege. Wer nicht will, findet Gründe.", "Where there's a will there's a way; without it, there are reasons."), by: tr("Sprichwort", "Proverb")),
            Quote(text: tr("Aufschreiben ist der erste Schritt, es ernst zu nehmen.", "Writing it down is the first step to taking it seriously."), by: fenn)
        ]
    }
}
