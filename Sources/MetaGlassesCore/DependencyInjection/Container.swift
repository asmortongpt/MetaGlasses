import Foundation
import Combine

// MARK: - Dependency Injection Container
public protocol DependencyContainerProtocol {
    func register<T>(_ type: T.Type, factory: @escaping () -> T)
    func register<T>(_ type: T.Type, name: String, factory: @escaping () -> T)
    func resolve<T>(_ type: T.Type) -> T
    func resolve<T>(_ type: T.Type, name: String) -> T
}

@MainActor
public final class DependencyContainer: DependencyContainerProtocol {

    // MARK: - Singleton
    public static let shared = DependencyContainer()

    // MARK: - Properties
    private var factories: [String: Any] = [:]
    private var singletons: [String: Any] = [:]
    private let queue = DispatchQueue(label: "com.metaglasses.di", attributes: .concurrent)

    // MARK: - Registration
    public func register<T>(_ type: T.Type, factory: @escaping () -> T) {
        register(type, name: String(describing: type), factory: factory)
    }

    public func register<T>(_ type: T.Type, name: String, factory: @escaping () -> T) {
        queue.async(flags: .barrier) { [weak self] in
            self?.factories[name] = factory
        }
    }

    public func registerSingleton<T>(_ type: T.Type, instance: T) {
        queue.async(flags: .barrier) { [weak self] in
            let key = String(describing: type)
            self?.singletons[key] = instance
        }
    }

    // MARK: - Resolution
    public func resolve<T>(_ type: T.Type) -> T {
        resolve(type, name: String(describing: type))
    }

    public func resolve<T>(_ type: T.Type, name: String) -> T {
        return queue.sync {
            // Check singletons first
            if let singleton = singletons[name] as? T {
                return singleton
            }

            // Check factories
            guard let factory = factories[name] as? () -> T else {
                fatalError("⚠️ Dependency '\(name)' not registered!")
            }

            return factory()
        }
    }

    // MARK: - Property Wrapper Support
    @propertyWrapper
    public struct Injected<T> {
        private let dependency: T

        public init() {
            self.dependency = DependencyContainer.shared.resolve(T.self)
        }

        public init(name: String) {
            self.dependency = DependencyContainer.shared.resolve(T.self, name: name)
        }

        public var wrappedValue: T {
            return dependency
        }
    }

    // MARK: - Builder Pattern
    public class Builder {
        private let container = DependencyContainer()

        @discardableResult
        public func register<T>(_ type: T.Type, factory: @escaping () -> T) -> Builder {
            container.register(type, factory: factory)
            return self
        }

        @discardableResult
        public func registerSingleton<T>(_ type: T.Type, instance: T) -> Builder {
            container.registerSingleton(type, instance: instance)
            return self
        }

        public func build() -> DependencyContainer {
            return container
        }
    }
}

// MARK: - Service Locator Pattern
public protocol ServiceLocator {
    func get<T>(_ type: T.Type) -> T
}

extension DependencyContainer: ServiceLocator {
    public func get<T>(_ type: T.Type) -> T {
        return resolve(type)
    }
}

// MARK: - Module Registration Protocol
public protocol ModuleRegistration {
    static func register(in container: DependencyContainer)
}