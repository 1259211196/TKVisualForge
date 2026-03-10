#include <metal_stdlib>
using namespace metal;

kernel void visual_forge_kernel(
    // 输入通道：原视频的 Y(亮度) 和 UV(色差)
    texture2d<float, access::read> inTextureY  [[texture(0)]],
    texture2d<float, access::read> inTextureUV [[texture(1)]],
    
    // 输出通道：洗白后的 Y 和 UV
    texture2d<float, access::write> outTextureY  [[texture(2)]],
    texture2d<float, access::write> outTextureUV [[texture(3)]],
    
    // 注入时间轴变量：让每一帧的洗白参数都在动态变化
    constant float &time [[buffer(0)]], 
    
    // 当前正在处理的像素网格坐标 (x, y)
    uint2 gridPosition [[thread_position_in_grid]]
) {
    uint widthY = outTextureY.get_width();
    uint heightY = outTextureY.get_height();
    
    // 边界安全检查，防止 GPU 越界导致 App 闪退
    if (gridPosition.x >= widthY || gridPosition.y >= heightY) {
        return;
    }
    
    // ====================================================
    // 🛡️ 第一层：像素梯度粉碎 (微观坐标空间映射，对抗 dHash)
    // ====================================================
    // 用正弦波制造 1.2 个像素的物理扭曲，人类肉眼绝对无法察觉，但相邻像素的明暗梯度已被彻底打乱
    float warpStrength = 1.2;
    int offsetX = int(sin(float(gridPosition.y) * 0.05 + time * 2.0) * warpStrength);
    int offsetY = int(cos(float(gridPosition.x) * 0.05 + time * 2.0) * warpStrength);
    
    // 计算出被扭曲后的假坐标，并确保它没有超出画面边缘
    uint2 samplePosY = uint2(
        clamp(int(gridPosition.x) + offsetX, 0, int(widthY - 1)),
        clamp(int(gridPosition.y) + offsetY, 0, int(heightY - 1))
    );
    
    // 从被扭曲的位置读取原本的亮度值
    float4 pixelY = inTextureY.read(samplePosY);
    
    // ====================================================
    // 🛡️ 第二层：动态光学呼吸 (低频重塑，对抗 pHash)
    // ====================================================
    // 计算当前像素到画面中心的距离，构造极慢的光学暗角
    float2 center = float2(widthY * 0.5, heightY * 0.5);
    float2 currentPos = float2(gridPosition.x, gridPosition.y);
    float dist = distance(currentPos, center) / distance(float2(0,0), center);
    
    // 暗角强度随时间在极慢呼吸 (约8秒一个明暗周期)，彻底摧毁 DCT 提取的低频轮廓
    float vignette = 0.05 + 0.03 * sin(time * 0.785); 
    // r 通道在 NV12 的 Y 纹理中代表灰阶亮度值
    pixelY.r = pixelY.r * (1.0 - dist * dist * vignette); 
    
    // 将洗白后的亮度写回输出通道
    outTextureY.write(pixelY, gridPosition);
    
    // ====================================================
    // 🛡️ 第三层：彩码微扰 (YUV 降维打击，对抗 vHash/色彩特征)
    // ====================================================
    uint widthUV = outTextureUV.get_width();
    uint heightUV = outTextureUV.get_height();
    
    // UV 贴图的尺寸通常是 Y 的一半 (4:2:0)，所以坐标要除以 2
    uint2 uvPosition = uint2(gridPosition.x / 2, gridPosition.y / 2);
    
    if (uvPosition.x < widthUV && uvPosition.y < heightUV) {
        // 让 UV 通道也跟随着 Y 通道产生同样的微观扭曲
        uint2 samplePosUV = uint2(
            clamp(int(uvPosition.x) + offsetX/2, 0, int(widthUV - 1)),
            clamp(int(uvPosition.y) + offsetY/2, 0, int(heightUV - 1))
        );
        
        float4 pixelUV = inTextureUV.read(samplePosUV);
        
        // 在 U(r) 和 V(g) 通道注入基于时间轴的相移，极度克制，不破坏高级反光感
        float colorShiftStrength = 0.015; // 严格控制在 1.5% 以内
        pixelUV.r = clamp(pixelUV.r + sin(time * 1.5) * colorShiftStrength, 0.0, 1.0);
        pixelUV.g = clamp(pixelUV.g + cos(time * 1.5) * colorShiftStrength, 0.0, 1.0);
        
        outTextureUV.write(pixelUV, uvPosition);
    }
}
