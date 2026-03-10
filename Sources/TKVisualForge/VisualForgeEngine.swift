import Foundation
import AVFoundation
import Metal
import CoreVideo

public class VisualForgeEngine {
    
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    
    // 极其关键：这是负责把我们的 Swift 代码和 .metal 文件里的公式连接起来的“管线”
    private var computePipelineState: MTLComputePipelineState?
    
    public init() {
        setupMetalEnvironment()
    }
    
    private func setupMetalEnvironment() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            print("[TKVisualForge] 🔴 致命错误：设备不支持 Metal")
            return
        }
        self.metalDevice = device
        self.commandQueue = device.makeCommandQueue()
        
        // 1. 初始化纹理缓存池 (防止 OOM 内存溢出)
        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache
        
        // 2. 加载我们的核武器：CoreShaders.metal 里的 visual_forge_kernel 函数
        // 注意：Swift Package Manager 会自动把 .metal 打包进 bundle
        guard let bundle = Bundle.module.url(forResource: "default", withExtension: "metallib"),
              let library = try? device.makeLibrary(URL: bundle),
              let kernelFunction = library.makeFunction(name: "visual_forge_kernel") else {
            print("[TKVisualForge] 🔴 致命错误：找不到 Metal 着色器函数")
            return
        }
        
        // 编译管线状态
        self.computePipelineState = try? device.makeComputePipelineState(function: kernelFunction)
        print("[TKVisualForge] 🟢 视觉锻造炉点火成功！GPU 管线已就绪。")
    }
    
    // ==========================================
    // 🎬 核心渲染流水线
    // ==========================================
    public func processVideo(inputURL: URL, outputURL: URL, completion: @escaping (Bool) -> Void) {
        print("[TKVisualForge] 开始深度洗白: \(inputURL.lastPathComponent)")
        
        // 【注：此处为了聚焦核心算法，省略了 AVAssetReader 和 AVAssetWriter 的几百行繁琐配置代码】
        // 假设我们已经配好了 Reader (读取 YUV 格式) 和 Writer (输出 H.265)...
        
        // 模拟逐帧读取的 While 循环
        /*
        while let sampleBuffer = readerTrackOutput.copyNextSampleBuffer() {
            // ⚠️ 极其关键的安全阀：处理完一帧必须立刻释放内存，否则处理 1080P 视频 5 秒钟必闪退！
            autoreleasepool {
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                
                // 执行 GPU 渲染
                self.renderFrameOnGPU(pixelBuffer: pixelBuffer)
                
                // 将处理完的 pixelBuffer 追加到 AVAssetWriter...
            }
        }
        */
        
        // 模拟完成回调
        completion(true)
    }
    
    // ==========================================
    // 🧠 GPU 纹理映射与并发派发 (终极动态版)
    // ==========================================
    private func renderFrameOnGPU(pixelBuffer: CVPixelBuffer, currentTime: Float) {
        guard let device = metalDevice,
              let commandQueue = commandQueue,
              let textureCache = textureCache,
              let pipelineState = computePipelineState else { return }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var yTextureRef: CVMetalTexture?
        var uvTextureRef: CVMetalTexture?
        
        // 映射 Y 通道和 UV 通道
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .r8Unorm, width, height, 0, &yTextureRef)
        CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, textureCache, pixelBuffer, nil, .rg8Unorm, width / 2, height / 2, 1, &uvTextureRef)
        
        guard let yTexture = CVMetalTextureGetTexture(yTextureRef!),
              let uvTexture = CVMetalTextureGetTexture(uvTextureRef!) else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(pipelineState)
        
        // 绑定输入与输出通道
        encoder.setTexture(yTexture, index: 0)
        encoder.setTexture(uvTexture, index: 1)
        encoder.setTexture(yTexture, index: 2)
        encoder.setTexture(uvTexture, index: 3)
        
        // 🌟 核心绝杀：将当前帧的播放秒数（时间戳）注射进 GPU 的 Buffer(0)
        // 这个 timeValue 会直接喂给着色器里的 constant float &time
        var timeValue = currentTime
        encoder.setBytes(&timeValue, length: MemoryLayout<Float>.size, index: 0)
        
        // 分配并发线程组
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(width: (width + threadGroupSize.width - 1) / threadGroupSize.width,
                                   height: (height + threadGroupSize.height - 1) / threadGroupSize.height,
                                   depth: 1)
        
        // 点火！执行并发计算
        encoder.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted() // 确保这一帧彻底渲染完毕再放行
    }
