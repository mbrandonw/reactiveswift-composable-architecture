import ComposableArchitecture
import ReactiveSwift
import XCTest

@testable import SwiftUICaseStudies

class ReusableComponentsDownloadComponentTests: XCTestCase {
  let downloadSubject = Signal<DownloadClient.Action, DownloadClient.Error>.pipe()
  let reducer = Reducer<
    DownloadComponentState<Int>, DownloadComponentAction, DownloadComponentEnvironment
  >
  .empty
  .downloadable(
    state: \.self,
    action: .self,
    environment: { $0 }
  )
  let scheduler = TestScheduler()

  func testDownloadFlow() {
    let store = TestStore(
      initialState: DownloadComponentState(
        alert: nil,
        id: 1,
        mode: .notDownloaded,
        url: URL(string: "https://www.pointfree.co")!
      ),
      reducer: reducer,
      environment: DownloadComponentEnvironment(
        downloadClient: .mock(
          download: { _, _ in self.downloadSubject.output.producer }
        ),
        mainQueue: self.scheduler
      )
    )

    store.assert(
      .send(.buttonTapped) {
        $0.mode = .startingToDownload
      },

      .do { self.downloadSubject.input.send(value: .updateProgress(0.2)) },
      .do { self.scheduler.advance() },
      .receive(.downloadClient(.success(.updateProgress(0.2)))) {
        $0.mode = .downloading(progress: 0.2)
      },

      .do { self.downloadSubject.input.send(value: .response(Data())) },
      .do { self.scheduler.advance(by: .seconds(1)) },
      .receive(.downloadClient(.success(.response(Data())))) {
        $0.mode = .downloaded
      },

      .do { self.downloadSubject.input.sendCompleted() },
      .do { self.scheduler.run() }
    )
  }

  func testDownloadThrottling() {
    let store = TestStore(
      initialState: DownloadComponentState(
        alert: nil,
        id: 1,
        mode: .notDownloaded,
        url: URL(string: "https://www.pointfree.co")!
      ),
      reducer: reducer,
      environment: DownloadComponentEnvironment(
        downloadClient: .mock(
          download: { _, _ in self.downloadSubject.output.producer }
        ),
        mainQueue: self.scheduler
      )
    )

    store.assert(
      .send(.buttonTapped) {
        $0.mode = .startingToDownload
      },

      .do { self.downloadSubject.input.send(value: .updateProgress(0.5)) },
      .do { self.scheduler.advance() },
      .receive(.downloadClient(.success(.updateProgress(0.5)))) {
        $0.mode = .downloading(progress: 0.5)
      },

      .do { self.downloadSubject.input.send(value: .updateProgress(0.6)) },
      .do { self.scheduler.advance(by: .milliseconds(500)) },

      .do { self.downloadSubject.input.send(value: .updateProgress(0.7)) },
      .do { self.scheduler.advance(by: .milliseconds(500)) },
      .receive(.downloadClient(.success(.updateProgress(0.7)))) {
        $0.mode = .downloading(progress: 0.7)
      },

      .do { self.downloadSubject.input.sendCompleted() },
      .do { self.scheduler.run() }
    )
  }

  func testCancelDownloadFlow() {
    let store = TestStore(
      initialState: DownloadComponentState(
        alert: nil,
        id: 1,
        mode: .notDownloaded,
        url: URL(string: "https://www.pointfree.co")!
      ),
      reducer: reducer,
      environment: DownloadComponentEnvironment(
        downloadClient: .mock(
          cancel: { _ in .fireAndForget { self.downloadSubject.input.sendCompleted() } },
          download: { _, _ in self.downloadSubject.output.producer }
        ),
        mainQueue: self.scheduler
      )
    )

    store.assert(
      .send(.buttonTapped) {
        $0.mode = .startingToDownload
      },

      .send(.buttonTapped) {
        $0.alert = DownloadAlert(
          primaryButton: .init(
            action: .alert(.cancelButtonTapped), label: "Cancel", type: .destructive
          ),
          secondaryButton: .init(
            action: .alert(.nevermindButtonTapped), label: "Nevermind", type: .default
          ),
          title: "Do you want to cancel downloading this map?"
        )
      },

      .send(.alert(.cancelButtonTapped)) {
        $0.alert = nil
        $0.mode = .notDownloaded
      },

      .do { self.scheduler.run() }
    )
  }

  func testDownloadFinishesWhileTryingToCancel() {
    let store = TestStore(
      initialState: DownloadComponentState(
        alert: nil,
        id: 1,
        mode: .notDownloaded,
        url: URL(string: "https://www.pointfree.co")!
      ),
      reducer: reducer,
      environment: DownloadComponentEnvironment(
        downloadClient: .mock(
          cancel: { _ in .fireAndForget { self.downloadSubject.input.sendCompleted() } },
          download: { _, _ in self.downloadSubject.output.producer }
        ),
        mainQueue: self.scheduler
      )
    )

    store.assert(
      .send(.buttonTapped) {
        $0.mode = .startingToDownload
      },

      .send(.buttonTapped) {
        $0.alert = DownloadAlert(
          primaryButton: .init(
            action: .alert(.cancelButtonTapped), label: "Cancel", type: .destructive
          ),
          secondaryButton: .init(
            action: .alert(.nevermindButtonTapped), label: "Nevermind", type: .default
          ),
          title: "Do you want to cancel downloading this map?"
        )
      },

      .do { self.downloadSubject.input.send(value: .response(Data())) },
      .do { self.scheduler.advance(by: .seconds(1)) },
      .receive(.downloadClient(.success(.response(Data())))) {
        $0.alert = nil
        $0.mode = .downloaded
      },

      .do { self.downloadSubject.input.sendCompleted() },
      .do { self.scheduler.run() }
    )
  }

  func testDeleteDownloadFlow() {
    let store = TestStore(
      initialState: DownloadComponentState(
        alert: nil,
        id: 1,
        mode: .downloaded,
        url: URL(string: "https://www.pointfree.co")!
      ),
      reducer: reducer,
      environment: DownloadComponentEnvironment(
        downloadClient: .mock(
          cancel: { _ in .fireAndForget { self.downloadSubject.input.sendCompleted() } },
          download: { _, _ in self.downloadSubject.output.producer }
        ),
        mainQueue: self.scheduler
      )
    )

    store.assert(
      .send(.buttonTapped) {
        $0.alert = DownloadAlert(
          primaryButton: .init(
            action: .alert(.deleteButtonTapped), label: "Delete", type: .destructive
          ),
          secondaryButton: .init(
            action: .alert(.nevermindButtonTapped), label: "Nevermind", type: .default
          ),
          title: "Do you want to delete this map from your offline storage?"
        )
      },

      .send(.alert(.deleteButtonTapped)) {
        $0.alert = nil
        $0.mode = .notDownloaded
      }
    )
  }
}

extension DownloadClient {
  static func mock(
    cancel: @escaping (AnyHashable) -> Effect<Never, Never> = { _ in fatalError() },
    download: @escaping (AnyHashable, URL) -> Effect<Action, Error> = { _, _ in fatalError() }
  ) -> Self {
    Self(
      cancel: cancel,
      download: download
    )
  }
}
