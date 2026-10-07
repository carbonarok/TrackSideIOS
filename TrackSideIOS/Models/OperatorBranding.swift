import SwiftUI

/// Brand colors for UK train operating companies by ATOC code
extension TrainOperator {
    var brandColor: Color {
        switch code.uppercased() {
        case "GW": return Color(red: 0.0, green: 0.29, blue: 0.24)   // GWR dark green
        case "SW": return Color(red: 0.91, green: 0.24, blue: 0.14)  // SWR red
        case "VT": return Color(red: 0.0, green: 0.0, blue: 0.0)     // Avanti black
        case "XC": return Color(red: 0.45, green: 0.0, blue: 0.18)   // CrossCountry burgundy
        case "SE": return Color(red: 0.0, green: 0.27, blue: 0.53)   // Southeastern blue
        case "TL": return Color(red: 0.88, green: 0.0, blue: 0.55)   // Thameslink pink
        case "GN": return Color(red: 0.33, green: 0.09, blue: 0.55)  // Great Northern purple
        case "SN": return Color(red: 0.0, green: 0.52, blue: 0.29)   // Southern green
        case "TP": return Color(red: 0.0, green: 0.35, blue: 0.65)   // TransPennine blue
        case "NT": return Color(red: 0.16, green: 0.22, blue: 0.47)  // Northern blue
        case "AW": return Color(red: 0.85, green: 0.11, blue: 0.16)  // TfW red
        case "SR": return Color(red: 0.0, green: 0.24, blue: 0.49)   // ScotRail blue
        case "EM": return Color(red: 0.34, green: 0.07, blue: 0.44)  // East Midlands purple
        case "LM": return Color(red: 0.47, green: 0.71, blue: 0.08)  // West Midlands lime
        case "GR": return Color(red: 0.78, green: 0.05, blue: 0.18)  // LNER red
        case "LE": return Color(red: 0.85, green: 0.14, blue: 0.17)  // Greater Anglia red
        case "CC": return Color(red: 0.6, green: 0.16, blue: 0.56)   // c2c magenta
        case "LO": return Color(red: 0.93, green: 0.47, blue: 0.05)  // London Overground orange
        case "HX": return Color(red: 0.33, green: 0.09, blue: 0.55)  // Heathrow Express purple
        case "ME": return Color(red: 1.0, green: 0.84, blue: 0.0)    // Merseyrail yellow
        case "CH": return Color(red: 0.0, green: 0.36, blue: 0.65)   // Chiltern blue
        case "GC": return Color(red: 0.17, green: 0.17, blue: 0.17)  // Grand Central dark
        case "LD": return Color(red: 0.0, green: 0.47, blue: 0.84)   // Lumo blue
        case "HT": return Color(red: 0.47, green: 0.13, blue: 0.53)  // Hull Trains purple
        case "CS": return Color(red: 0.0, green: 0.44, blue: 0.45)   // Caledonian Sleeper teal
        case "ES": return Color(red: 0.17, green: 0.24, blue: 0.42)  // Eurostar navy
        case "IL": return Color(red: 0.0, green: 0.42, blue: 0.65)   // Island Line blue
        case "XR": return Color(red: 0.39, green: 0.29, blue: 0.68)  // Elizabeth line purple
        default: return .secondary
        }
    }
}
