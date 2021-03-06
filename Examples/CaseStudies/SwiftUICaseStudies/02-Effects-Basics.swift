import Combine
import ComposableArchitecture
import ReactiveSwift
import SwiftUI

private let readMe = """
  This screen demonstrates how to introduce side effects into a feature built with the \
  Composable Architecture.

  A side effect is a unit of work that needs to be performed in the outside world. For example, an \
  API request needs to reach an external service over HTTP, which brings with it lots of \
  uncertainty and complexity.

  Many things we do in our applications involve side effects, such as timers, database requests, \
  file access, socket connections, and anytime a scheduler is involved (such as debouncing, \
  throttling and delaying), and they are typically difficult to test.

  This application has two simple side effects:

  • Each time you count down the number will be incremented back up after a delay of 1 second.
  • Tapping "Number fact" will trigger an API request to load a piece of trivia about that number.

  Both effects are handled by the reducer, and a full test suite is written to confirm that the \
  effects behave in the way we expect.
  """

// MARK: - Feature domain

struct EffectsBasicsState: Equatable {
  var count = 0
  var isNumberFactRequestInFlight = false
  var numberFact: String?
}

enum EffectsBasicsAction: Equatable {
  case decrementButtonTapped
  case incrementButtonTapped
  case numberFactButtonTapped
  case numberFactResponse(Result<String, NumbersApiError>)
}

struct NumbersApiError: Error, Equatable {}

struct EffectsBasicsEnvironment {
  var mainQueue: DateScheduler
  var numberFact: (Int) -> Effect<String, NumbersApiError>

  static let live = EffectsBasicsEnvironment(
    mainQueue: QueueScheduler.main,
    numberFact: liveNumberFact(for:)
  )
}

// MARK: - Feature business logic

let effectsBasicsReducer = Reducer<
  EffectsBasicsState, EffectsBasicsAction, EffectsBasicsEnvironment
> { state, action, environment in
  switch action {
  case .decrementButtonTapped:
    state.count -= 1
    state.numberFact = nil
    // Return an effect that re-increments the count after 1 second.
    return Effect(value: EffectsBasicsAction.incrementButtonTapped)
      .delay(1, on: environment.mainQueue)

  case .incrementButtonTapped:
    state.count += 1
    state.numberFact = nil
    return .none

  case .numberFactButtonTapped:
    state.isNumberFactRequestInFlight = true
    state.numberFact = nil
    // Return an effect that fetches a number fact from the API and returns the
    // value back to the reducer's `numberFactResponse` action.
    return environment.numberFact(state.count)
      .observe(on: environment.mainQueue)
      .catchToEffect()
      .map(EffectsBasicsAction.numberFactResponse)

  case let .numberFactResponse(.success(response)):
    state.isNumberFactRequestInFlight = false
    state.numberFact = response
    return .none

  case .numberFactResponse(.failure):
    state.isNumberFactRequestInFlight = false
    return .none
  }
}

// MARK: - Feature view

struct EffectsBasicsView: View {
  let store: Store<EffectsBasicsState, EffectsBasicsAction>

  var body: some View {
    WithViewStore(self.store) { viewStore in
      Form {
        Section(header: Text(readMe)) {
          EmptyView()
        }

        Section(
          footer: Button("Number facts provided by numbersapi.com") {
            UIApplication.shared.open(URL(string: "http://numbersapi.com")!)
          }
        ) {
          HStack {
            Spacer()
            Button("−") { viewStore.send(.decrementButtonTapped) }
            Text("\(viewStore.count)")
              .font(Font.body.monospacedDigit())
            Button("+") { viewStore.send(.incrementButtonTapped) }
            Spacer()
          }
          .buttonStyle(BorderlessButtonStyle())

          Button("Number fact") { viewStore.send(.numberFactButtonTapped) }
          if viewStore.isNumberFactRequestInFlight {
            ActivityIndicator()
          }

          viewStore.numberFact.map(Text.init)
        }
      }
    }
    .navigationBarTitle("Effects")
  }
}

// MARK: - Feature SwiftUI previews

struct EffectsBasicsView_Previews: PreviewProvider {
  static var previews: some View {
    NavigationView {
      EffectsBasicsView(
        store: Store(
          initialState: EffectsBasicsState(),
          reducer: effectsBasicsReducer,
          environment: EffectsBasicsEnvironment(
            mainQueue: QueueScheduler.main,
            numberFact: liveNumberFact(for:))
        )
      )
    }
  }
}

// This is the "live" trivia dependency that reaches into the outside world to fetch trivia.
// Typically this live implementation of the dependency would live in its own module so that the
// main feature doesn't need to compile it.
private func liveNumberFact(for n: Int) -> Effect<String, NumbersApiError> {
  return Effect<String, NumbersApiError> { observer, lifetime in
    let task = URLSession.shared.dataTask(with: URL(string: "http://numbersapi.com/\(n)/trivia")!) {
      data, response, error in
      if let data = data {
        observer.send(value: String.init(decoding: data, as: UTF8.self))
      } else {
        observer.send(value: "\(n) is a good number Brent")
      }
      observer.sendCompleted()
    }

    lifetime += AnyDisposable(task.cancel)
    task.resume()
  }
}
