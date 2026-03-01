//
//  PortWorldApp.swift
//  PortWorld
//
//  Created by Pierre Haas on 28/02/2026.
//

import Foundation
import MWDATCore
import SwiftUI

@main
struct PortWorldApp: App {
  @StateObject private var wearablesViewModel: WearablesViewModel

  init() {
    do {
      try Wearables.configure()
    } catch {
#if DEBUG
      NSLog("[PortWorld] Failed to configure Wearables SDK: \(error)")
#endif
    }
    self._wearablesViewModel = StateObject(wrappedValue: WearablesViewModel(wearables: Wearables.shared))
  }

  var body: some Scene {
    WindowGroup {
      MainAppView(wearables: Wearables.shared, viewModel: wearablesViewModel)
        .alert("Error", isPresented: $wearablesViewModel.showError) {
          Button("OK") {
            wearablesViewModel.dismissError()
          }
        } message: {
          Text(wearablesViewModel.errorMessage)
        }
      RegistrationView(viewModel: wearablesViewModel)
    }
  }
}
