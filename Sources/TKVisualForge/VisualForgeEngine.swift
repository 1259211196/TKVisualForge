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
    // 🎬 核心渲染流水线 (全链路贯通版)
    // ==========================================
    public func processVideo(inputURL: URL, outputURL: URL, completion: @escaping (Bool) -> Void) {
        print("[TKVisualForge] 🚀 开始深度洗白全流程: \(inputURL.lastPathComponent)")
        
        let asset = AVAsset(url: inputURL)
        
        // 1. 获取视频和音频轨道
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            print("[TKVisualForge] 🔴 错误：找不到视频轨道")
            completion(false)
            return
        }
        let audioTrack = asset.tracks(withMediaType: .audio).first // 音频可能没有，所以是可选的
        
        do {
            // 2. 初始化 Reader (拆解机) 和 Writer (压制机)
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
            
            // --- 视频读取配置 (强制指定 NV12 格式给 Metal 用) ---
            let readerVideoSettings: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ]
            let videoReaderOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: readerVideoSettings)
            videoReaderOutput.alwaysCopiesSampleData = false // 尽量减少内存复制
            reader.add(videoReaderOutput)
            
            // --- 视频写入配置 (原生 Apple HEVC 硬件编码) ---
            let writerVideoSettings: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.hevc, // H.265，画质更好，体积更小
                AVVideoWidthKey: videoTrack.naturalSize.width,
                AVVideoHeightKey: videoTrack.naturalSize.height
                // 此处可以注入您的 V12 硬件参数，比如 AVVideoCompressionPropertiesKey
            ]
            let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: writerVideoSettings)
            videoWriterInput.expectsMediaDataInRealTime = false
            videoWriterInput.transform = videoTrack.preferredTransform // 保持原视频的方向(竖屏/横屏)
            writer.add(videoWriterInput)
            
            // --- 音频通道配置 (无损搬运) ---
            var audioReaderOutput: AVAssetReaderTrackOutput?
            var audioWriterInput: AVAssetWriterInput?
            if let aTrack = audioTrack {
                audioReaderOutput = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
                reader.add(audioReaderOutput!)
                
                audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
                audioWriterInput!.expectsMediaDataInRealTime = false
                writer.add(audioWriterInput!)
            }
            
            // 3. 点火！开始流水线
            reader.startReading()
            writer.startWriting()
            writer.startSession(atSourceTime: .zero)
            
            // 4. 开辟后台线程进行逐帧渲染，不卡死 UI
            let processingQueue = DispatchQueue(label: "com.V12.visualForgeQueue")
            
            videoWriterInput.requestMediaDataWhenReady(on: processingQueue) {
                while videoWriterInput.isReadyForMoreMediaData {
                    // 读取下一帧
                    guard let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() else {
                        // 视频读完了，标记视频通道结束
                        videoWriterInput.markAsFinished()
                        
                        // 视频处理完后，处理音频通道
                        if let aOutput = audioReaderOutput, let aInput = audioWriterInput {
                            while let audioBuffer = aOutput.copyNextSampleBuffer() {
                                if aInput.isReadyForMoreMediaData {
                                    aInput.append(audioBuffer)
                                }
                            }
                            aInput.markAsFinished()
                        }
                        
                        // 彻底完成收尾工作
                        writer.finishWriting {
                            print("[TKVisualForge] 🟢 洗白完成！已生成纯净原生视频。")
                            DispatchQueue.main.async { completion(true) }
                        }
                        break // 跳出循环
                    }
                    
                    // 🌟 极其关键：内存防爆阀与 GPU 渲染调用 🌟
                    autoreleasepool {
                        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                        
                        // 提取当前帧的时间戳 (秒)，喂给我们的 Metal 动态时间轴
                        let time = Float(CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
                        
                        // 【GPU 介入】：原址重构这帧画面！
                        self.renderFrameOnGPU(pixelBuffer: pixelBuffer, currentTime: time)
                        
                        // 因为是原址修改 (Zero-Copy)，我们修改了 pixelBuffer 后，
                        // 原本的 sampleBuffer 里面的画面就已经变了！直接把它塞给压制机！
                        videoWriterInput.append(sampleBuffer)
                    }
                }
            }
            
        } catch {
            print("[TKVisualForge] 🔴 管线崩溃: \(error.localizedDescription)")
            completion(false)
        }
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
