import SwiftUI
import ChoosVoieCore

struct ContentView: View {
    private static let sampleSRT = """
    1
    00:00:01,000 --> 00:00:02,500
    Merhaba dünya

    2
    00:00:03,250 --> 00:00:04,500
    İkinci
    """

    private static let drafts = CueIO.parseSRT(sampleSRT)

    var body: some View {
        NavigationStack {
            List {
                Section("Çekirdek bağlantısı") {
                    LabeledContent("ChoosVoieCore SRT replik sayısı", value: "\(Self.drafts.count)")
                    ForEach(Array(Self.drafts.enumerated()), id: \.offset) { _, d in
                        Text("\(CueIO.srtTimestamp(d.startSec)) – \(d.text)")
                    }
                }
                Section("Spikes") {
                    NavigationLink("S0.1 STT") { SpikePlaceholderView(title: "S0.1 STT") }
                    NavigationLink("S0.7 Ducking") { SpikePlaceholderView(title: "S0.7 Ducking") }
                    NavigationLink("S0.3 Kayıt gecikmesi") { SpikePlaceholderView(title: "S0.3 Kayıt gecikmesi") }
                }
            }
            .navigationTitle("ChoosVoie")
        }
    }
}
