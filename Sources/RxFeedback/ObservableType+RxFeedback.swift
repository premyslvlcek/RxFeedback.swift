//
//  ObservableType+Extensions.swift
//  RxFeedback
//
//  Created by Krunoslav Zaher on 4/30/17.
//  Copyright © 2017 Krunoslav Zaher. All rights reserved.
//

import RxCocoa
import RxSwift

extension ObservableType where E == Any {
    /// Feedback loop
    public typealias Feedback<State, Event, Context> = (ObservableSchedulerContext<State>, Context) -> Observable<Event>

    /**
     The system simulation will be started upon subscription and stopped after subscription is disposed.

     System state is represented as a `State` parameter.
     Events are represented by the `Event` parameter.

     - parameter initialState: The initial state of the system.
     - parameter reduce: Calculates the new system state from the existing state and a transition event (system integrator, reducer).
     - parameter feedback: The feedback loops that produce events depending on the current system state.
     - returns: The current state of the system.
     */
    public static func system<State, Event, Context>(
        initialState: State,
        reduce: @escaping (State, Event) -> State,
        scheduler: ImmediateSchedulerType,
        context: Context,
        feedback: [Feedback<State, Event, Context>]
    ) -> Observable<State> {
        return Observable<State>.deferred {
            let replaySubject = ReplaySubject<State>.create(bufferSize: 1)

            let asyncScheduler = scheduler.async

            let events: Observable<Event> = Observable.merge(
                feedback.map { feedback in
                    let state = ObservableSchedulerContext(source: replaySubject.asObservable(), scheduler: asyncScheduler)
                    return feedback(state, context)
                }
            )
            // This is protection from accidental ignoring of scheduler so
            // reentracy errors can be avoided
            .observeOn(CurrentThreadScheduler.instance)

            return events.scan(initialState, accumulator: reduce)
                .do(
                    onNext: { output in
                        replaySubject.onNext(output)
                    }, onSubscribed: {
                        replaySubject.onNext(initialState)
                    }
                )
                .subscribeOn(scheduler)
                .startWith(initialState)
                .observeOn(scheduler)
        }
    }

    /**
     The system simulation will be started upon subscription and stopped after subscription is disposed.

     System state is represented as a `State` parameter.
     Events are represented by the `Event` parameter.

     - parameter initialState: The initial state of the system.
     - parameter reduce: Calculates the new system state from the existing state and a transition event (system integrator, reducer).
     - parameter feedback: The feedback loops that produce events depending on the current system state.
     - returns: The current state of the system.
     */
    public static func system<State, Event, Context>(
        initialState: State,
        reduce: @escaping (State, Event) -> State,
        scheduler: ImmediateSchedulerType,
        context: Context,
        feedback: Feedback<State, Event, Context>...
    ) -> Observable<State> {
        return system(initialState: initialState, reduce: reduce, scheduler: scheduler, context: context, feedback: feedback)
    }
}

extension SharedSequenceConvertibleType where E == Any, SharingStrategy == DriverSharingStrategy {
    /// Feedback loop
    public typealias Feedback<State, Event, Context> = (Driver<State>, Context) -> Signal<Event>

    /**
     The system simulation will be started upon subscription and stopped after subscription is disposed.

     System state is represented as a `State` parameter.
     Events are represented by the `Event` parameter.

     - parameter initialState: The initial state of the system.
     - parameter reduce: Calculates the new system state from the existing state and a transition event (system integrator, reducer).
     - parameter feedback: The feedback loops that produce events depending on the current system state.
     - returns: The current state of the system.
     */
    public static func system<State, Event, Context>(
        initialState: State,
        reduce: @escaping (State, Event) -> State,
        context: Context,
        feedback: [Feedback<State, Event, Context>]
    ) -> Driver<State> {
        let observableFeedbacks: [(ObservableSchedulerContext<State>, Context) -> Observable<Event>] = feedback.map { feedback in
            return { sharedSequence, context in
                feedback(sharedSequence.source.asDriver(onErrorDriveWith: Driver<State>.empty()), context)
                    .asObservable()
            }
        }

        return Observable<Any>.system(
            initialState: initialState,
            reduce: reduce,
            scheduler: SharingStrategy.scheduler,
            context: context,
            feedback: observableFeedbacks
        )
        .asDriver(onErrorDriveWith: .empty())
    }

    /**
     The system simulation will be started upon subscription and stopped after subscription is disposed.

     System state is represented as a `State` parameter.
     Events are represented by the `Event` parameter.

     - parameter initialState: The initial state of the system.
     - parameter reduce: Calculates the new system state from the existing state and a transition event (system integrator, reducer).
     - parameter feedback: The feedback loops that produce events depending on the current system state.
     - returns: The current state of the system.
     */
    public static func system<State, Event, Context>(
        initialState: State,
        reduce: @escaping (State, Event) -> State,
        context: Context,
        feedback: Feedback<State, Event, Context>...
    ) -> Driver<State> {
        return system(initialState: initialState, reduce: reduce, context: context, feedback: feedback)
    }
}

extension ImmediateSchedulerType {
    var async: ImmediateSchedulerType {
        // This is a hack because of reentrancy. We need to make sure events are being sent async.
        // In case MainScheduler is being used MainScheduler.asyncInstance is used to make sure state is modified async.
        // If there is some unknown scheduler instance (like TestScheduler), just use it.
        return (self as? MainScheduler).map { _ in MainScheduler.asyncInstance } ?? self
    }
}

/// Tuple of observable sequence and corresponding scheduler context on which that observable
/// sequence receives elements.
public struct ObservableSchedulerContext<Element>: ObservableType {
    public typealias E = Element

    /// Source observable sequence
    public let source: Observable<Element>

    /// Scheduler on which observable sequence receives elements
    public let scheduler: ImmediateSchedulerType

    /// Initializes self with source observable sequence and scheduler
    ///
    /// - parameter source: Source observable sequence.
    /// - parameter scheduler: Scheduler on which source observable sequence receives elements.
    public init(source: Observable<Element>, scheduler: ImmediateSchedulerType) {
        self.source = source
        self.scheduler = scheduler
    }

    public func subscribe<O: ObserverType>(_ observer: O) -> Disposable where O.E == E {
        return source.subscribe(observer)
    }
}
