//
//  TrackSideWidgetsBundle.swift
//  TrackSideWidgets
//
//  Created by Kristian Carbonaro on 06/10/2026.
//

import WidgetKit
import SwiftUI

@main
struct TrackSideWidgetsBundle: WidgetBundle {
    var body: some Widget {
        DepartureWidget()
        LegLiveActivity()
        JourneyLiveActivity()
        TrainLiveActivity()
    }
}
