import Foundation
import AVFoundation
import Metal
import CoreVideo

public class VisualForgeEngine {
    
    // GPU 核心三剑客
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    
    // 极其关键：纹理缓存池，用于在视频的 CVPixelBuffer 和 Metal 纹理之间无损/无内存泄漏地传递数据
    private var textureCache: CVMetalTextureCache?
    
    public init() {
        setupMetalEnvironment()
    }
    
    private func setupMetalEnvironment() {
        // 1. 获取这台 iPhone 的物理 GPU
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[TKVisualForge] 🔴 致命错误：该设备不支持 Metal 渲染引擎")
            return
        }
        self.metalDevice = device
        self.commandQueue = device.makeCommandQueue()
        
        // 2. 初始化核心内存防爆池 (Texture Cache)
        var cache: CVMetalTextureCache?
        let result = CVMetalTextureCacheCreate(kCFAllocatorDefault, 
                                               nil, 
                                               device, 
                                               nil, 
                                               &cache)
        
        if result == kCVReturnSuccess {
            self.textureCache = cache
            print("[TKVisualForge] 🟢 视觉锻造炉点火成功！GPU 内存池已就绪。")
        } else {
            print("[TKVisualForge] 🔴 致命错误：无法创建纹理缓存池，错误码：\(result)")
        }
    }
    
    // 对外暴露的测试接口，V12 以后将通过这个入口把视频丢进来
    public func startProcessing(videoURL: URL) {
        print("[TKVisualForge] 收到视频任务，准备进行深度洗白: \(videoURL.lastPathComponent)")
        // 下一步，我们将在这里编写 AVAssetReader 的逐帧读取逻辑...
    }
}
