//
//  ContentView.swift
//  PhotoWatermark
//
//  Created by ⛰️ on 2025/9/26.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - Codable Color Wrapper
// SwiftUI.Color and NSColor are not directly Codable. This wrapper makes them so.
struct CodableColor: Codable, Hashable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    var color: Color {
        Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    init(color: Color) {
        let nsColor = NSColor(color)
        self.red = nsColor.redComponent
        self.green = nsColor.greenComponent
        self.blue = nsColor.blueComponent
        self.alpha = nsColor.alphaComponent
    }
}


// MARK: - Watermark Settings Model (The heart of the template system)
struct WatermarkSettings: Codable, Equatable {
    var id = UUID() // For identifying templates
    var name: String = "未命名模板"
    
    // Common properties
    var watermarkType: ContentView.WatermarkType = .text
    var position: CGSize = .zero
    
    // Text watermark properties
    var text: String = "Hello World"
    var fontName: String = "Helvetica Neue"
    var fontSize: CGFloat = 48
    var textColor: CodableColor = CodableColor(color: .white)
    var textOpacity: Double = 0.5

    // Text style properties
   var isBold: Bool = false
   var isItalic: Bool = false

   // Text stroke properties
   var hasStroke: Bool = false
   var strokeColor: CodableColor = CodableColor(color: .black)
   var strokeWidth: CGFloat = 2
    
    // Image watermark properties
    var imageData: Data? = nil // Store image as Data to be Codable
    var imageScale: CGFloat = 0.3
    var imageOpacity: Double = 1.0
    
    // Static property for a default template
    static var `default`: WatermarkSettings {
        WatermarkSettings()
    }
}


// MARK: - Template Manager (Handles saving & loading from UserDefaults)
class TemplateManager: ObservableObject {
    @Published var templates: [WatermarkSettings] = []
    private let templatesKey = "watermarkTemplates"
    private let lastSettingsKey = "lastWatermarkSettings"

    init() {
        loadTemplates()
    }

    func loadTemplates() {
        guard let data = UserDefaults.standard.data(forKey: templatesKey) else { return }
        if let decodedTemplates = try? JSONDecoder().decode([WatermarkSettings].self, from: data) {
            self.templates = decodedTemplates
        }
    }

    func saveTemplate(_ settings: WatermarkSettings) {
        // If a template with the same ID exists, update it. Otherwise, add it.
        if let index = templates.firstIndex(where: { $0.id == settings.id }) {
            templates[index] = settings
        } else {
            templates.append(settings)
        }
        saveAllTemplates()
    }

    func deleteTemplate(at offsets: IndexSet) {
        templates.remove(atOffsets: offsets)
        saveAllTemplates()
    }
    
    private func saveAllTemplates() {
        if let encoded = try? JSONEncoder().encode(templates) {
            UserDefaults.standard.set(encoded, forKey: templatesKey)
        }
    }

    func saveLastSettings(_ settings: WatermarkSettings) {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: lastSettingsKey)
        }
    }

    func loadLastSettings() -> WatermarkSettings? {
        guard let data = UserDefaults.standard.data(forKey: lastSettingsKey) else { return nil }
        return try? JSONDecoder().decode(WatermarkSettings.self, from: data)
    }
}


// MARK: - Data Models (Unchanged)
struct ImageFile: Identifiable, Hashable {
    let id = UUID()
    let bookmarkData: Data
    func getURL() -> URL? {
        var isStale = false
        do {
            return try URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
        } catch {
            print("Error resolving bookmark data: \(error)")
            return nil
        }
    }
}
enum ExportScope: String, CaseIterable, Identifiable {
    case all = "导出所有图片", selected = "仅导出选中图片"; var id: Self { self }
}
enum NamingRule: String, CaseIterable, Identifiable {
    case keepOriginal = "覆盖原文件", addPrefix = "添加前缀", addSuffix = "添加后缀"; var id: Self { self }
}
enum ExportFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG"; var id: Self { self }
}

enum ScaleMode: String, CaseIterable, Identifiable {
    case none = "原始尺寸"
    case byWidth = "按宽度"
    case byHeight = "按高度"
    case byPercentage = "按百分比"
    var id: Self { self }
}

// MARK: - Main Content View
struct ContentView: View {
    // MARK: - State Properties
    @Environment(\.scenePhase) private var scenePhase

    @State private var imageFiles: [ImageFile] = []
    @State private var selectedImageFileID: ImageFile.ID?

    // --- Refactored State ---
    @StateObject private var templateManager = TemplateManager()
    @State private var settings: WatermarkSettings = .default
    // ---
    
    @State private var dragOffset: CGSize = .zero
    @State private var showingExportSheet = false
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var previewSize: CGSize = .zero
    @State private var showingSaveTemplateAlert = false
    @State private var newTemplateName: String = "我的模板"
    
    enum LeftPanelTab: String, CaseIterable {
    case settings = "设置"
    case templates = "模板"
      }
      @State private var selectedTab: LeftPanelTab = .settings

    private let availableFonts: [String] = NSFontManager.shared.availableFonts.sorted()
    
    private var selectedImageURL: URL? {
        guard let selectedID = selectedImageFileID,
              let file = imageFiles.first(where: { $0.id == selectedID }) else { return nil }
        return file.getURL()
    }

    // Computed property to get NSImage from Data for the watermark
    private var watermarkImage: NSImage? {
        guard let data = settings.imageData else { return nil }
        return NSImage(data: data)
    }
    
    enum WatermarkType: String, CaseIterable, Identifiable, Codable {
        case text = "文字水印", image = "图片水印"; var id: Self { self }
    }

    // MARK: - Body
    var body: some View {
        HSplitView {
            leftPanel
            rightPanel
        }
        .frame(minWidth: 1000, minHeight: 850)
        .sheet(isPresented: $showingExportSheet) {
            ExportSettingsView(
                settings: $settings,
                previewSize: self.previewSize,
                imageFiles: $imageFiles,
                selectedImageFileID: $selectedImageFileID,
                showingAlert: $showingAlert,
                alertTitle: $alertTitle,
                alertMessage: $alertMessage
            )
        }
        .alert("保存模板", isPresented: $showingSaveTemplateAlert, actions: {
            TextField("模板名称", text: $newTemplateName)
            Button("保存", action: saveCurrentSettingsAsTemplate)
            Button("取消", role: .cancel) { }
        }, message: {
            Text("请输入一个名称来保存当前的水印设置。")
        })
        .alert(isPresented: $showingAlert) {
            Alert(title: Text(alertTitle), message: Text(alertMessage), dismissButton: .default(Text("好的")))
        }
        .onAppear {
            if let lastSettings = templateManager.loadLastSettings() {
                self.settings = lastSettings
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background || newPhase == .inactive {
                templateManager.saveLastSettings(settings)
            }
        }
    }

    // MARK: - UI Components

private var leftPanel: some View {
    VStack(spacing: 0) {
        // Import Controls (这部分不变)
        HStack {
            Button(action: openImagePicker) { Label("选择图片", systemImage: "photo.on.rectangle.angled") }
            Button(action: openFolderPicker) { Label("选择文件夹", systemImage: "folder") }
        }.padding()

        // Image List (这部分不变)
        Text("已导入图片 (\(imageFiles.count))").font(.headline).padding([.leading, .trailing, .bottom], 8)
        List(selection: $selectedImageFileID) {
            ForEach(imageFiles) { file in
                if let url = file.getURL() {
                    let _ = url.startAccessingSecurityScopedResource()
                    ImageRow(url: url).onDisappear { url.stopAccessingSecurityScopedResource() }.tag(file.id)
                        .contextMenu { Button(role: .destructive) { deleteImage(id: file.id) } label: { Label("删除", systemImage: "trash") } }
                }
            }
        }.frame(minHeight: 150)
        
        Divider()

        // --- 从这里开始是重构的 UI ---
        // 使用分段控件来切换视图
        Picker("视图选择", selection: $selectedTab) {
            ForEach(LeftPanelTab.allCases, id: \.self) { tab in
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding()

        // 根据选择的 Tab 显示不同的内容
        if selectedTab == .settings {
            ScrollView {
                watermarkSettings.padding([.horizontal, .bottom])
            }
        } else {
            // 模板视图不需要 ScrollView，因为 List 内部自带滚动
            templateManagement.padding([.horizontal, .bottom])
        }
        // --- 重构结束 ---
        
        Spacer()
        
        Divider()
        
        // Export Button Area (这部分不变)
        VStack {
            Button(action: {
                guard !imageFiles.isEmpty else {
                    showAlert(title: "无图片", message: "请先导入需要添加水印的图片。")
                    return
                }
                showingExportSheet = true
            }) {
                Label("导出图片...", systemImage: "square.and.arrow.down.on.square").frame(maxWidth: .infinity)
            }.padding().controlSize(.large)
        }.background(Color(NSColor.windowBackgroundColor))
    }
    .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
}
    
    private var rightPanel: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.opacity(0.2)
                    .onDrop(of: [.fileURL], delegate: ImageDropDelegate(imageFiles: $imageFiles, selectedImageFileID: $selectedImageFileID))
                    .onAppear { self.previewSize = geometry.size }
                    .onChange(of: geometry.size) { _, newSize in self.previewSize = newSize }
                if let selectedURL = selectedImageURL {
                    let _ = selectedURL.startAccessingSecurityScopedResource()
                    if let nsImage = NSImage(contentsOf: selectedURL) {
                        Image(nsImage: nsImage).resizable().aspectRatio(contentMode: .fit).padding().onDisappear { selectedURL.stopAccessingSecurityScopedResource() }
                    } else { Text("无法加载图片") }
                } else { VStack { Text("请从左侧选择图片或拖拽图片到此处").font(.title).foregroundColor(.secondary) } }
               if selectedImageURL != nil {
                if settings.watermarkType == .text {
                    // 使用 ZStack 来实现描边效果
                    ZStack {
                        // 描边层 (在底层)
                        if settings.hasStroke {
                            Text(settings.text)
                                .strikethrough(false) // Workaround to apply stroke in SwiftUI
                                .font(.custom(settings.fontName, size: settings.fontSize))
                                .fontWeight(settings.isBold ? .bold : .regular)
                                .italic(settings.isItalic)
                                .foregroundStyle(settings.strokeColor.color)
                                .overlay(
                                    // The actual text on top
                                    Text(settings.text)
                                        .font(.custom(settings.fontName, size: settings.fontSize))
                                        .fontWeight(settings.isBold ? .bold : .regular)
                                        .italic(settings.isItalic)
                                        .foregroundColor(settings.textColor.color)
                                        .opacity(settings.textOpacity)
                                )
                                // A simple way to control stroke width in preview
                                .scaleEffect(1 + (settings.strokeWidth / settings.fontSize))
                        }
                     
                        // 主要文字层 (如果无描边，则只显示这一层)
                        Text(settings.text)
                            .font(.custom(settings.fontName, size: settings.fontSize))
                            .fontWeight(settings.isBold ? .bold : .regular)
                            .italic(settings.isItalic)
                            .foregroundColor(settings.textColor.color)
                            .opacity(settings.textOpacity)
                            .shadow(color: .black.opacity(0.6), radius: 4, x: 2, y: 2)
                    }
                    .padding()
                    .offset(x: settings.position.width + dragOffset.width, y: settings.position.height + dragOffset.height)
                    .gesture(dragGesture())
                    
                } else if let image = watermarkImage {
                    Image(nsImage: image)
                        .resizable().aspectRatio(contentMode: .fit)
                        .frame(width: image.size.width * settings.imageScale)
                        .opacity(settings.imageOpacity)
                        .offset(x: settings.position.width + dragOffset.width, y: settings.position.height + dragOffset.height)
                        .gesture(dragGesture())
                }
                PositionGridView(watermarkPosition: $settings.position) { alignment in setWatermarkPosition(alignment) }
                    .frame(width: 180).padding(12).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12)).padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
              }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
private var templateManagement: some View {
    VStack {
        // --- 标题和保存按钮部分不变 ---
        HStack {
            Text("水印模板").font(.title2).bold()
            Spacer()
            Button {
                newTemplateName = "我的模板 \(templateManager.templates.count + 1)"
                showingSaveTemplateAlert = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
            }
            .buttonStyle(.plain) // 使用 .plain 样式让它看起来更像一个图标按钮
            .help("保存当前设置为模板")
        }

        // --- 列表部分重构 ---
        if !templateManager.templates.isEmpty {
            List(selection: Binding(
                get: { settings.id },
                set: { selectedId in
                    // 当选择发生变化时，找到对应的模板并应用
                    if let newSettings = templateManager.templates.first(where: { $0.id == selectedId }) {
                        self.settings = newSettings
                    }
                }
            )) {
                ForEach(templateManager.templates, id: \.id) { template in
                    Text(template.name)
                        .tag(template.id) // 必须有 .tag 才能让 List selection 工作
                }
                .onDelete(perform: templateManager.deleteTemplate)
            }
            .frame(minHeight: 50, maxHeight: .infinity) // 允许列表填满剩余空间
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            
        } else {
            // ... (没有模板的提示不变) ...
            Text("没有已保存的模板").foregroundColor(.secondary).padding()
        }
    }
}


private var watermarkSettings: some View {
    VStack(spacing: 20) {
        Text("水印设置").font(.title2).bold()
        Picker("水印类型", selection: $settings.watermarkType) {
            ForEach(WatermarkType.allCases) { type in Text(type.rawValue).tag(type) }
        }.pickerStyle(.segmented).padding(.bottom, 10)

        if settings.watermarkType == .text {
            Form {
                Section(header: Text("内容")) {
                    TextField("水印文字:", text: $settings.text)
                    ColorPicker("颜色:", selection: Binding(get: { settings.textColor.color }, set: { settings.textColor = CodableColor(color: $0) }))
                    Slider(value: $settings.textOpacity, in: 0...1) { Text("透明度:") }
                }
                
                Section(header: Text("字体")) {
                    Picker("字体:", selection: $settings.fontName) {
                        ForEach(availableFonts, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        Text("字号:")
                        TextField("", value: $settings.fontSize, formatter: NumberFormatter()).frame(width: 50)
                        Stepper("", value: $settings.fontSize, in: 8...288)
                    }
                    // --- 新增的 Toggle ---
                    Toggle("粗体", isOn: $settings.isBold)
                    Toggle("斜体", isOn: $settings.isItalic)
                }

                // --- 新增的 Section ---
                Section(header: Text("描边 (可选)")) {
                    Toggle("启用描边", isOn: $settings.hasStroke)
                    if settings.hasStroke {
                        ColorPicker("描边颜色:", selection: Binding(get: { settings.strokeColor.color }, set: { settings.strokeColor = CodableColor(color: $0) }))
                        HStack {
                            Text("描边宽度:")
                            Slider(value: $settings.strokeWidth, in: 1...20)
                        }
                    }
                }
            }
        } else {
            // ... (图片水印设置部分保持不变)
            VStack {
                if let image = watermarkImage {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(height: 60)
                        .padding(8).background(Color.black.opacity(0.2)).cornerRadius(8)
                    Text(image.name() ?? "已选择图片").font(.caption).lineLimit(1).truncationMode(.middle)
                } else { Text("未选择水印图片").foregroundColor(.secondary).frame(height: 60) }
                Button(action: openImageWatermarkPicker) { Label("选择图片...", systemImage: "photo") }.padding(.bottom)
                Form {
                    Slider(value: $settings.imageScale, in: 0.05...1.0) { Text("缩放:") }
                    Slider(value: $settings.imageOpacity, in: 0...1) { Text("透明度:") }
                }
            }
        }
    }
}

    // MARK: - Helper Functions
    private func saveCurrentSettingsAsTemplate() {
        var newTemplate = settings
        newTemplate.id = UUID() // Assign a new ID for the new template
        newTemplate.name = newTemplateName
        templateManager.saveTemplate(newTemplate)
    }
    
    private func dragGesture() -> some Gesture {
        DragGesture()
            .onChanged { value in dragOffset = value.translation }
            .onEnded { value in
                settings.position.width += value.translation.width
                settings.position.height += value.translation.height
                dragOffset = .zero
            }
    }

    private func openImageWatermarkPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        if panel.runModal() == .OK, let url = panel.url {
            guard url.startAccessingSecurityScopedResource() else {
                showAlert(title: "权限错误", message: "无法访问所选图片。")
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            if let imageData = try? Data(contentsOf: url) {
                settings.imageData = imageData
            }
        }
    }

    private func getWatermarkPreviewSize() -> CGSize {
        if settings.watermarkType == .text {
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: settings.fontName, size: settings.fontSize) ?? .systemFont(ofSize: settings.fontSize)]
            return NSAttributedString(string: settings.text, attributes: attributes).size()
        } else if let image = watermarkImage {
            return CGSize(width: image.size.width * settings.imageScale, height: image.size.height * settings.imageScale)
        }
        return .zero
    }

    private func setWatermarkPosition(_ alignment: WatermarkAlignment) {
        guard let selectedURL = selectedImageURL, let nsImage = NSImage(contentsOf: selectedURL) else { return }
        let imageSize = nsImage.size
        let viewSize = self.previewSize
        let watermarkSize = getWatermarkPreviewSize()
        let imageAspectRatio = imageSize.width / imageSize.height
        let viewAspectRatio = viewSize.width / viewSize.height
        var renderRect = CGRect(origin: .zero, size: viewSize)
        if imageAspectRatio > viewAspectRatio {
            renderRect.size.height = viewSize.width / imageAspectRatio
            renderRect.origin.y = (viewSize.height - renderRect.size.height) / 2
        } else {
            renderRect.size.width = viewSize.height * imageAspectRatio
            renderRect.origin.x = (viewSize.width - renderRect.size.width) / 2
        }
        let padding: CGFloat = 10.0
        let halfWidth = (renderRect.width / 2) - (watermarkSize.width / 2) - padding
        let halfHeight = (renderRect.height / 2) - (watermarkSize.height / 2) - padding
        var newPosition = CGSize.zero
        switch alignment {
        case .topLeft:      newPosition = CGSize(width: -halfWidth, height: -halfHeight)
        case .top:          newPosition = CGSize(width: 0,           height: -halfHeight)
        case .topRight:     newPosition = CGSize(width: halfWidth,  height: -halfHeight)
        case .left:         newPosition = CGSize(width: -halfWidth, height: 0)
        case .center:       newPosition = .zero
        case .right:        newPosition = CGSize(width: halfWidth,  height: 0)
        case .bottomLeft:   newPosition = CGSize(width: -halfWidth, height: halfHeight)
        case .bottom:       newPosition = CGSize(width: 0,           height: halfHeight)
        case .bottomRight:  newPosition = CGSize(width: halfWidth,  height: halfHeight)
        }
        dragOffset = .zero
        settings.position = newPosition
    }
    
    private func showAlert(title: String, message: String) {
        self.alertTitle = title; self.alertMessage = message; self.showingAlert = true
    }
    
    private func openImagePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.jpeg, .png, .tiff, .bmp, .heic]
        if panel.runModal() == .OK { addImages(from: panel.urls) }
    }

    private func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let folderURL = panel.url {
            guard folderURL.startAccessingSecurityScopedResource() else {
                showAlert(title: "权限错误", message: "无法访问文件夹内容。"); return
            }
            defer { folderURL.stopAccessingSecurityScopedResource() }
            let fileManager = FileManager.default
            let supportedExtensions = ["jpg", "jpeg", "png", "tiff", "bmp", "heic"]
            if let enumerator = fileManager.enumerator(at: folderURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
                let urls = enumerator.allObjects.compactMap { $0 as? URL }.filter { supportedExtensions.contains($0.pathExtension.lowercased()) }
                addImages(from: urls)
            }
        }
    }

    private func addImages(from urls: [URL]) {
        for url in urls {
            do {
                let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                let newFile = ImageFile(bookmarkData: bookmarkData)
                if !imageFiles.contains(where: { $0.getURL() == url }) { imageFiles.append(newFile) }
            } catch {
                print("Error creating bookmark for \(url): \(error)")
                showAlert(title: "导入错误", message: "无法为文件创建安全书签：\n\(url.lastPathComponent)")
            }
        }
        if selectedImageFileID == nil, let firstFile = imageFiles.first { selectedImageFileID = firstFile.id }
    }
    
    private func deleteImage(id: ImageFile.ID) {
        if let index = imageFiles.firstIndex(where: { $0.id == id }) {
            imageFiles.remove(at: index)
            if selectedImageFileID == id { selectedImageFileID = imageFiles.first?.id }
        }
    }
}

// MARK: - Export Settings View (Modal Sheet)
struct ExportSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var settings: WatermarkSettings
    let previewSize: CGSize
    @Binding var imageFiles: [ImageFile]
    @Binding var selectedImageFileID: ImageFile.ID?
    @Binding var showingAlert: Bool
    @Binding var alertTitle: String
    @Binding var alertMessage: String
    @State private var exportScope: ExportScope = .all
    @State private var namingRule: NamingRule = .addSuffix
    @State private var exportFormat: ExportFormat = .png
    @State private var customPrefix: String = "wm_"
    @State private var customSuffix: String = "_watermarked"
    @State private var jpegQuality: Double = 0.8
    @State private var isExporting = false
    @State private var scaleMode: ScaleMode = .none
    @State private var scaleValue: Int = 100
    
    private var exportButtonText: String {
        switch exportScope {
        case .all: return "开始导出 \(imageFiles.count) 张图片"
        case .selected: return "开始导出 1 张图片"
        }
    }

    var body: some View {
        VStack {
            Text("导出设置").font(.largeTitle).padding()
            Form {
                Section(header: Text("导出范围")) {
                    Picker("导出:", selection: $exportScope) {
                        ForEach(ExportScope.allCases) { scope in Text(scope.rawValue).tag(scope) }
                    }.pickerStyle(SegmentedPickerStyle()).disabled(selectedImageFileID == nil)
                }
                Section(header: Text("文件选项")) {
                    Picker("输出格式:", selection: $exportFormat) { ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) } }
                    if exportFormat == .jpeg { Slider(value: $jpegQuality, in: 0...1) { Text("JPEG 质量:") } }
                    Picker("命名规则:", selection: $namingRule) { ForEach(NamingRule.allCases) { Text($0.rawValue).tag($0) } }
                    if namingRule == .addPrefix { TextField("前缀:", text: $customPrefix) }
                    if namingRule == .addSuffix { TextField("后缀:", text: $customSuffix) }
                }
                  Section(header: Text("图片尺寸 (可选)")) {
                     Picker("缩放模式:", selection: $scaleMode) {
                        ForEach(ScaleMode.allCases) { mode in
                              Text(mode.rawValue).tag(mode)
                        }
                     }
                     
                     if scaleMode != .none {
                        HStack {
                              if scaleMode == .byPercentage {
                                 Text("百分比:")
                                 TextField("", value: $scaleValue, formatter: NumberFormatter())
                                    .multilineTextAlignment(.trailing)
                                 Text("%")
                              } else {
                                 Text(scaleMode == .byWidth ? "宽度:" : "高度:")
                                 TextField("", value: $scaleValue, formatter: NumberFormatter())
                                    .multilineTextAlignment(.trailing)
                                 Text("px")
                              }
                        }
                     }
                  }
            }
            Spacer()
            if isExporting { ProgressView("正在导出...").padding() }
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(action: { Task { await exportImages() } }) { Text(exportButtonText) }.disabled(isExporting).keyboardShortcut(.defaultAction)
            }.padding()
        }.frame(minWidth: 400, idealWidth: 500, minHeight: 450).padding()
        .onAppear { if selectedImageFileID == nil { exportScope = .all } }
    }
    
    private func showAlert(title: String, message: String) {
        self.alertTitle = title; self.alertMessage = message; self.showingAlert = true
    }
    
    private func exportImages() async {
        isExporting = true
        defer { isExporting = false }
        let filesToExport: [ImageFile]
        switch exportScope {
        case .all: filesToExport = imageFiles
        case .selected:
            if let selectedID = selectedImageFileID, let selectedFile = imageFiles.first(where: { $0.id == selectedID }) {
                filesToExport = [selectedFile]
            } else { showAlert(title: "导出错误", message: "没有选中的图片可导出。"); return }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.title = "选择导出文件夹"
        if panel.runModal() == .OK, let outputDirectory = panel.url {
            let sourceURLs = filesToExport.compactMap { $0.getURL() }
            let sourceDirectories = Set(sourceURLs.map { $0.deletingLastPathComponent() })
            if sourceDirectories.contains(outputDirectory) && namingRule == .keepOriginal {
                showAlert(title: "导出失败", message: "选择了“覆盖原文件”时，不能将文件导出到原始文件夹，请选择其他位置或更改命名规则。"); return
            }
            guard outputDirectory.startAccessingSecurityScopedResource() else {
                showAlert(title: "权限错误", message: "无法获得对目标文件夹的写入权限。"); return
            }
            defer { outputDirectory.stopAccessingSecurityScopedResource() }
            var successCount = 0
            for file in filesToExport {
                guard let url = file.getURL() else { continue }
                guard url.startAccessingSecurityScopedResource() else { continue }
                guard let originalImage = NSImage(contentsOf: url) else { url.stopAccessingSecurityScopedResource(); continue }
                let watermarkedImage = await renderWatermarkedImage(for: originalImage)
                let newFileName = getOutputFileName(for: url)
                let outputURL = outputDirectory.appendingPathComponent(newFileName)
                if save(image: watermarkedImage, to: outputURL) { successCount += 1 }
                url.stopAccessingSecurityScopedResource()
            }
            await MainActor.run {
                showAlert(title: "导出完成", message: "\(successCount) / \(filesToExport.count) 张图片已成功保存到: \(outputDirectory.path)")
                dismiss()
            }
        }
    }
    


@MainActor
private func renderWatermarkedImage(for image: NSImage) -> NSImage {
    // ... (图片缩放和画布创建逻辑保持不变)
    guard let originalCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image }
    let originalSize = image.size
    let outputSize: CGSize
    switch scaleMode {
    case .none: outputSize = originalSize
    case .byWidth: let newWidth = CGFloat(scaleValue); let newHeight = (newWidth / originalSize.width) * originalSize.height; outputSize = CGSize(width: newWidth, height: newHeight)
    case .byHeight: let newHeight = CGFloat(scaleValue); let newWidth = (newHeight / originalSize.height) * originalSize.width; outputSize = CGSize(width: newWidth, height: newHeight)
    case .byPercentage: let factor = CGFloat(scaleValue) / 100.0; outputSize = CGSize(width: originalSize.width * factor, height: originalSize.height * factor)
    }
    guard let context = CGContext(data: nil, width: Int(outputSize.width), height: Int(outputSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    context.draw(originalCGImage, in: CGRect(origin: .zero, size: outputSize))
    let nsGraphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsGraphicsContext
    let imageAspectRatio = outputSize.width / outputSize.height
    let previewAspectRatio = previewSize.width / previewSize.height
    var renderRect = CGRect(origin: .zero, size: previewSize)
    if imageAspectRatio > previewAspectRatio {
        renderRect.size.height = previewSize.width / imageAspectRatio
        renderRect.origin.y = (previewSize.height - renderRect.size.height) / 2
    } else {
        renderRect.size.width = previewSize.height * imageAspectRatio
        renderRect.origin.x = (previewSize.width - renderRect.size.width) / 2
    }
    let scale = outputSize.width / renderRect.width

    // --- 从这里开始替换 ---
    if settings.watermarkType == .text {
        // 1. 根据 isBold 和 isItalic 获取正确的字体
        let fontManager = NSFontManager.shared
        var fontTraits: NSFontTraitMask = []
        if settings.isBold { fontTraits.insert(.boldFontMask) }
        if settings.isItalic { fontTraits.insert(.italicFontMask) }
        
        guard let baseFont = NSFont(name: settings.fontName, size: settings.fontSize * scale),
              let finalFont = fontManager.font(withFamily: baseFont.familyName ?? settings.fontName, traits: fontTraits, weight: 5, size: settings.fontSize * scale) else {
            NSGraphicsContext.restoreGraphicsState(); return image
        }
        
        // 2. 构建 NSAttributedString 的属性字典
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.6)
        shadow.shadowOffset = NSSize(width: 2 * scale, height: 2 * scale)
        shadow.shadowBlurRadius = 4 * scale
        
        var attributes: [NSAttributedString.Key: Any] = [
            .font: finalFont,
            .foregroundColor: NSColor(settings.textColor.color).withAlphaComponent(settings.textOpacity),
            .shadow: shadow
        ]
        
        // 3. 如果启用了描边，添加描边属性
        if settings.hasStroke {
            // 使用负值可以让描边和填充同时存在
            attributes[.strokeWidth] = -(settings.strokeWidth * scale)
            attributes[.strokeColor] = NSColor(settings.strokeColor.color)
        }
        
        let watermarkString = NSAttributedString(string: settings.text, attributes: attributes)
        let watermarkSize = watermarkString.size()
        let drawPoint = CGPoint(x: (outputSize.width - watermarkSize.width) / 2 + settings.position.width * scale, y: (outputSize.height - watermarkSize.height) / 2 - settings.position.height * scale)
        watermarkString.draw(at: drawPoint)
        
    } else if let imageData = settings.imageData, let watermarkImage = NSImage(data: imageData) {
        // (图片水印逻辑不变)
        let scaledWatermarkSize = CGSize(width: watermarkImage.size.width * settings.imageScale * scale, height: watermarkImage.size.height * settings.imageScale * scale)
        let drawRect = CGRect(x: (outputSize.width - scaledWatermarkSize.width) / 2 + settings.position.width * scale, y: (outputSize.height - scaledWatermarkSize.height) / 2 - settings.position.height * scale, width: scaledWatermarkSize.width, height: scaledWatermarkSize.height)
        watermarkImage.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: settings.imageOpacity)
    }
    // --- 替换结束 ---

    NSGraphicsContext.restoreGraphicsState()
    guard let watermarkedCGImage = context.makeImage() else { return image }
    return NSImage(cgImage: watermarkedCGImage, size: outputSize)
}
    
    private func getOutputFileName(for url: URL) -> String {
        let stem = url.deletingPathExtension().lastPathComponent
        let finalExt = exportFormat == .png ? "png" : "jpg"
        switch namingRule {
        case .keepOriginal: return "\(stem).\(finalExt)"
        case .addPrefix: return "\(customPrefix)\(stem).\(finalExt)"
        case .addSuffix: return "\(stem)\(customSuffix).\(finalExt)"
        }
    }
    
    private func save(image: NSImage, to url: URL) -> Bool {
        guard let tiffData = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiffData) else { return false }
        var imageData: Data?
        switch exportFormat {
        case .png: imageData = bitmap.representation(using: .png, properties: [:])
        case .jpeg: imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: jpegQuality])
        }
        do { try imageData?.write(to: url); return true } catch { print("Failed to save image to \(url): \(error)"); return false }
    }
}

// MARK: - Subviews and Delegates
struct ImageRow: View {
    let url: URL
    @State private var thumbnail: NSImage?
    var body: some View {
        HStack(spacing: 12) {
            if let image = thumbnail {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).frame(width: 40, height: 40).clipped().cornerRadius(4)
            } else {
                ZStack { Color(NSColor.windowBackgroundColor); Image(systemName: "photo.on.rectangle.questionmark").foregroundColor(.secondary) }.frame(width: 40, height: 40).cornerRadius(4)
            }
            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Spacer()
        }.padding(.vertical, 4).onAppear(perform: generateThumbnail)
    }

    private func generateThumbnail() {
        guard thumbnail == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return }
            let maxDimension = 120.0
            let thumbnailOptions = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceShouldCacheImmediately: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: maxDimension] as CFDictionary
            let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions)
            DispatchQueue.main.async { if let cgImage = cgImage { self.thumbnail = NSImage(cgImage: cgImage, size: .zero) } }
        }
    }
}

enum WatermarkAlignment { case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight }

struct PositionGridView: View {
    @Binding var watermarkPosition: CGSize
    var onSelect: (WatermarkAlignment) -> Void
    private let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
    private let alignments: [WatermarkAlignment] = [.topLeft, .top, .topRight, .left, .center, .right, .bottomLeft, .bottom, .bottomRight]
    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(alignments, id: \.self) { alignment in
                Button(action: { onSelect(alignment) }) {
                    Image(systemName: systemName(for: alignment)).font(.title2).frame(maxWidth: .infinity, minHeight: 40)
                }.buttonStyle(.bordered).help(tooltip(for: alignment))
            }
        }
    }
private func systemName(for alignment: WatermarkAlignment) -> String {
    switch alignment {
    case .topLeft: return "arrow.up.left"
    case .top: return "arrow.up"
    case .topRight: return "arrow.up.right"
    case .left: return "arrow.left"
    case .center: return "scope"
    case .right: return "arrow.right"
    case .bottomLeft: return "arrow.down.left"
    case .bottom: return "arrow.down"
    case .bottomRight: return "arrow.down.right"
    // --- 新增代码在这里 ---
    default: return "questionmark" // 为任何未预见的情况提供一个默认图标
    // --- 新增代码结束 ---
    }
}
private func tooltip(for alignment: WatermarkAlignment) -> String {
    switch alignment {
    case .topLeft: return "左上角"
    case .top: return "顶部居中"
    case .topRight: return "右上角"
    case .left: return "左侧居中"
    case .center: return "正中心"
    case .right: return "右侧居中"
    case .bottomLeft: return "左下角"
    case .bottom: return "底部居中"
    case .bottomRight: return "右下角"
    // --- 新增代码在这里 ---
    default: return "未知位置" // 提供默认提示
    // --- 新增代码结束 ---
    }
}
}

struct ImageDropDelegate: DropDelegate {
    @Binding var imageFiles: [ImageFile]
    @Binding var selectedImageFileID: ImageFile.ID?
    func validateDrop(info: DropInfo) -> Bool { info.hasItemsConforming(to: [.fileURL]) }
    func performDrop(info: DropInfo) -> Bool {
        let providers = info.itemProviders(for: [.fileURL])
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                guard let url = url, error == nil else { return }
                do {
                    let bookmarkData = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    DispatchQueue.main.async {
                        let newFile = ImageFile(bookmarkData: bookmarkData)
                        if !self.imageFiles.contains(where: { $0.getURL() == url }) {
                            self.imageFiles.append(newFile)
                            if self.selectedImageFileID == nil { self.selectedImageFileID = newFile.id }
                        }
                    }
                } catch { print("Error creating bookmark for dropped file \(url): \(error)") }
            }
        }
        return true
    }
}

struct ContentView_Previews: PreviewProvider { static var previews: some View { ContentView() } }
extension CGSize { static func +(lhs: CGSize, rhs: CGSize) -> CGSize { CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height) } }