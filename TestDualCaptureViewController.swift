import UIKit

class TestDualCaptureViewController: UIViewController {

    private let titleLabel: UILabel = {
        let label = UILabel()
        label.text = "MetaGlasses AI"
        label.font = .systemFont(ofSize: 36, weight: .bold)
        label.textColor = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let subtitleLabel: UILabel = {
        let label = UILabel()
        label.text = "110+ AI Features Ready"
        label.font = .systemFont(ofSize: 17)
        label.textColor = UIColor(red: 0, green: 0.478, blue: 1, alpha: 1)
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "Tap to configure signing in Xcode"
        label.font = .systemFont(ofSize: 14)
        label.textColor = .gray
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .white

        // Add subviews
        view.addSubview(titleLabel)
        view.addSubview(subtitleLabel)
        view.addSubview(statusLabel)

        // Setup constraints
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            subtitleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            subtitleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            subtitleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

            statusLabel.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 40),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20)
        ])

        // Animate labels
        animateLabels()
    }

    private func animateLabels() {
        titleLabel.alpha = 0
        subtitleLabel.alpha = 0
        statusLabel.alpha = 0

        UIView.animate(withDuration: 0.8, delay: 0.2, options: .curveEaseOut) {
            self.titleLabel.alpha = 1
        }

        UIView.animate(withDuration: 0.8, delay: 0.5, options: .curveEaseOut) {
            self.subtitleLabel.alpha = 1
        }

        UIView.animate(withDuration: 0.8, delay: 0.8, options: .curveEaseOut) {
            self.statusLabel.alpha = 1
        }
    }
}
