import UIKit
import Vision

struct VisionLabel {
    var name: String
    var confidence: Float
}

struct VisionAnalysis {
    var labels: [VisionLabel]
    var recognizedText: String
    var barcodes: [String]

    /// 拼成一段给文本模型看的描述
    var promptDescription: String {
        var parts: [String] = []
        if !labels.isEmpty {
            let top = labels.prefix(6).map { "\($0.name)（\(Int($0.confidence * 100))%）" }
            parts.append("画面元素：" + top.joined(separator: "、"))
        }
        if !recognizedText.isEmpty {
            parts.append("图中文字：" + String(recognizedText.prefix(400)))
        }
        if !barcodes.isEmpty {
            parts.append("条码内容：" + barcodes.joined(separator: "、"))
        }
        if parts.isEmpty { return "这张图没有识别出明显的物体或文字。" }
        return parts.joined(separator: "\n")
    }
}

enum ImageAnalyzer {

    static func analyze(_ image: UIImage) async throws -> VisionAnalysis {
        try await Task.detached(priority: .userInitiated) {
            try analyzeSync(image)
        }.value
    }

    private static func analyzeSync(_ image: UIImage) throws -> VisionAnalysis {
        guard let cgImage = image.cgImage else {
            throw NSError(domain: "ImageAnalyzer", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "这张图片读不出来，换一张试试。"])
        }

        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])

        let classify = VNClassifyImageRequest()
        let text = VNRecognizeTextRequest()
        text.recognitionLevel = .accurate
        text.usesLanguageCorrection = true
        text.recognitionLanguages = ["zh-Hans", "en-US"]

        let barcode = VNDetectBarcodesRequest()

        do {
            try handler.perform([classify, text, barcode])
        } catch {
            throw NSError(domain: "ImageAnalyzer", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "本地识图失败了：\(error.localizedDescription)"])
        }

        var labels: [VisionLabel] = []
        if let observations = classify.results {
            for observation in observations.prefix(10) where observation.confidence > 0.25 {
                labels.append(VisionLabel(name: ChineseLabels.translate(observation.identifier),
                                          confidence: observation.confidence))
            }
        }

        var recognized: [String] = []
        if let observations = text.results {
            for observation in observations {
                if let candidate = observation.topCandidates(1).first {
                    recognized.append(candidate.string)
                }
            }
        }

        var barcodes: [String] = []
        if let observations = barcode.results {
            for observation in observations {
                if let payload = observation.payloadStringValue, !payload.isEmpty {
                    barcodes.append(payload)
                }
            }
        }

        return VisionAnalysis(labels: labels,
                              recognizedText: recognized.joined(separator: "\n"),
                              barcodes: barcodes)
    }
}

extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// 把系统返回的英文标签换成中文，查不到就原样显示。
enum ChineseLabels {
    static func translate(_ identifier: String) -> String {
        let key = identifier.lowercased()
        if let hit = table[key] { return hit }
        let parts = key.split(separator: ",")
        if let first = parts.first, let hit = table[String(first)] { return hit }
        return identifier
    }

    private static let table: [String: String] = [
        "dog": "狗", "cat": "猫", "bird": "鸟", "fish": "鱼", "insect": "昆虫",
        "tree": "树", "flower": "花", "plant": "植物", "leaf": "叶子", "grass": "草",
        "sky": "天空", "cloud": "云", "water": "水面", "sea": "海", "beach": "沙滩",
        "mountain": "山", "forest": "森林", "desert": "沙漠", "snow": "雪",
        "building": "建筑", "house": "房子", "room": "室内", "kitchen": "厨房",
        "office": "办公室", "classroom": "教室", "store": "商店", "street": "街道",
        "car": "汽车", "bicycle": "自行车", "motorcycle": "摩托车", "bus": "公交车",
        "train": "火车", "airplane": "飞机", "boat": "船", "truck": "卡车",
        "person": "人", "face": "人脸", "hand": "手", "food": "食物", "fruit": "水果",
        "vegetable": "蔬菜", "bread": "面包", "cake": "蛋糕", "drink": "饮料",
        "phone": "手机", "computer": "电脑", "keyboard": "键盘", "laptop": "笔记本电脑",
        "book": "书", "paper": "纸", "pen": "笔", "clock": "钟表", "lamp": "台灯",
        "table": "桌子", "chair": "椅子", "bed": "床", "window": "窗户", "door": "门",
        "clothing": "衣物", "shirt": "衬衫", "shoe": "鞋", "hat": "帽子", "bag": "包",
        "toy": "玩具", "ball": "球", "game": "游戏", "screen": "屏幕", "poster": "海报",
        "text": "文字", "document": "文档", "sign": "标牌", "logo": "标志",
        "art": "图画", "painting": "绘画", "sculpture": "雕塑", "pattern": "图案",
        "machine": "机器", "tool": "工具", "furniture": "家具", "bottle": "瓶子",
        "cup": "杯子", "box": "盒子", "package": "包裹", "electronics": "电子产品"
    ]
}
