import SwiftUI
import UIKit

/// Ein Bild zum Zoomen und Verschieben – mit Fingerspreizen und Doppeltipp.
///
/// UIKit statt SwiftUI-Gesten: `UIScrollView` bringt Trägheit, Anschlag an den Rändern
/// und das Zentrieren gleich mit. In SwiftUI müsste man das alles nachbauen, und es
/// fühlt sich nie ganz nach iOS an.
struct ZoomableImageView: UIViewRepresentable {

    let image: UIImage

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        if imageView.image !== image {
            imageView.image = image
            scrollView.zoomScale = 1
        }
        imageView.frame = CGRect(origin: .zero, size: scrollView.bounds.size)
        scrollView.contentSize = scrollView.bounds.size
        context.coordinator.center(in: scrollView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center(in: scrollView)
        }

        /// Hält das Bild in der Mitte, solange es kleiner als der Bildschirm ist.
        func center(in scrollView: UIScrollView) {
            guard let imageView else { return }
            let bounds = scrollView.bounds.size
            let content = imageView.frame.size
            let dx = max(0, (bounds.width - content.width) / 2)
            let dy = max(0, (bounds.height - content.height) / 2)
            scrollView.contentInset = UIEdgeInsets(top: dy, left: dx, bottom: dy, right: dx)
        }

        @objc func doubleTapped(_ recognizer: UITapGestureRecognizer) {
            guard let scrollView = recognizer.view as? UIScrollView, let imageView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                // Auf den angetippten Punkt zoomen, nicht auf die Mitte.
                let point = recognizer.location(in: imageView)
                let scale: CGFloat = 3
                let size = CGSize(width: scrollView.bounds.width / scale, height: scrollView.bounds.height / scale)
                let rect = CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                  width: size.width, height: size.height)
                scrollView.zoom(to: rect, animated: true)
            }
        }
    }
}

/// Vollbild für die Etikettfotos: blätterbar zwischen den Seiten, jede zoombar.
struct LabelZoomView: View {

    let pages: [LabelPage]
    @State var selection: Int

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    ZoomableImageView(image: page.image)
                        .tag(index)
                        .accessibilityLabel(page.title)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: pages.count > 1 ? .always : .never))
            .background(Color.black)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(pages.indices.contains(selection) ? pages[selection].title : "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
