# Код в панели

```swift
@MainActor
public final class AppModel {
    public func ask(_ text: String) {
        dispatch(.turnStarted)
    }
}
```

```bash
swift build --package-path Packages/GeraniaKit --scratch-path ../build/swiftpm
swift test --package-path Packages/GeraniaKit --scratch-path ../build/swiftpm
```

После блока кода обычный текст продолжает разговор.
