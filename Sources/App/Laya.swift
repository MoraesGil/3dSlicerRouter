import Foundation

/// Julgamento tipado do daemon LAYA local (opcional), só para arquivos sem `printer_model`.
/// Endpoint: `defaults write com.moraesdev.3dslicerrouter LayaEndpoint <url>`; `off` desliga.
enum Laya {
    static var endpoint: URL? {
        let value = UserDefaults.standard.string(forKey: "LayaEndpoint") ?? "http://127.0.0.1:8100/v1/systemone"
        return value == "off" ? nil : URL(string: value)
    }
    /// Abaixo disso o router pergunta ao dono.
    static let minProbability = 0.75

    struct Guess { let app: SlicerApp; let probability: Double }

    static func classify(info: ThreeMFInfo, fileName: String) -> Guess? {
        let facts = [
            "file name: \(fileName)",
            "creator application: \(info.application ?? "unknown")",
            "printer preset: \(info.printerSettingsID ?? "none")",
            "process preset: \(info.printSettingsID ?? "none")",
            "objects: \(info.objectNames.prefix(12).joined(separator: ", "))",
        ].joined(separator: "\n")
        let body: [String: Any] = [
            "state": ["file": facts],
            "questions": ["slicer": [
                "type": "choice",
                "instructions": "Which slicer app should open the 3MF project described in `file`?",
                "criteria": [
                    "bambu_studio": "Bambu Lab printers (A1, A1 mini, P1S, P1P, X1C, H2D, H2C), BambuStudio projects, @BBL presets",
                    "snapmaker_orca": "Snapmaker printers (U1, J1, Artisan, A350), Snapmaker Orca or OrcaSlicer projects",
                    "unknown": "no evidence for either printer family",
                ],
            ]],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body), let json = post(payload),
              let answer = (json["answers"] as? [String: Any])?["slicer"] as? [String: Any],
              let choice = answer["choice"] as? String,
              let p = (answer["probabilities"] as? [String: Double])?[choice] else { return nil }
        switch choice {
        case "bambu_studio": return Guess(app: .bambuStudio, probability: p)
        case "snapmaker_orca": return Guess(app: .snapmakerOrca, probability: p)
        default: return nil
        }
    }

    /// Até 3 tentativas em timeout/5xx (agora, +2 s, +8 s); 4xx e conexão recusada não se repetem.
    private static func post(_ payload: Data) -> [String: Any]? {
        guard let endpoint else { return nil }
        for wait in [0.0, 2, 8] {
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            var request = URLRequest(url: endpoint, timeoutInterval: 15)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            var result: (Data?, URLResponse?, Error?)
            let done = DispatchSemaphore(value: 0)
            URLSession.shared.dataTask(with: request) { d, r, e in result = (d, r, e); done.signal() }.resume()
            done.wait()
            let status = (result.1 as? HTTPURLResponse)?.statusCode ?? 0
            if status == 200, let d = result.0 { return try? JSONSerialization.jsonObject(with: d) as? [String: Any] }
            if (400..<500).contains(status) { return nil }
            // Daemon não instalado/rodando: não vale esperar retry.
            if (result.2 as? URLError)?.code == .cannotConnectToHost { return nil }
        }
        return nil
    }
}
