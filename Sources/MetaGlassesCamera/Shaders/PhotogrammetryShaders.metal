//
//  PhotogrammetryShaders.metal
//  MetaGlassesCamera
//
//  Production Metal compute shaders for photogrammetry and super-resolution
//

#include <metal_stdlib>
using namespace metal;

// MARK: - Super Resolution Kernel

struct EnhancementParams {
    float sharpness;
    float contrast;
    float saturation;
    float denoise;
};

// Bicubic interpolation weight function
inline float bicubicWeight(float x) {
    x = abs(x);
    if (x <= 1.0) {
        return (1.5 * x - 2.5) * x * x + 1.0;
    } else if (x < 2.0) {
        return ((-0.5 * x + 2.5) * x - 4.0) * x + 2.0;
    }
    return 0.0;
}

// Bicubic upsampling with enhancement
kernel void superResolutionKernel(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant EnhancementParams &params [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    // Get dimensions
    uint inWidth = inputTexture.get_width();
    uint inHeight = inputTexture.get_height();
    uint outWidth = outputTexture.get_width();
    uint outHeight = outputTexture.get_height();

    // Bounds check
    if (gid.x >= outWidth || gid.y >= outHeight) {
        return;
    }

    // Calculate input coordinates (bicubic upsampling 2x)
    float scaleX = float(inWidth) / float(outWidth);
    float scaleY = float(inHeight) / float(outHeight);
    float srcX = (float(gid.x) + 0.5) * scaleX - 0.5;
    float srcY = (float(gid.y) + 0.5) * scaleY - 0.5;

    int x0 = int(floor(srcX));
    int y0 = int(floor(srcY));
    float fx = srcX - float(x0);
    float fy = srcY - float(y0);

    // Bicubic interpolation (16 sample points)
    float4 color = float4(0.0);
    float weightSum = 0.0;

    for (int j = -1; j <= 2; j++) {
        for (int i = -1; i <= 2; i++) {
            int sx = clamp(x0 + i, 0, int(inWidth) - 1);
            int sy = clamp(y0 + j, 0, int(inHeight) - 1);

            float wx = bicubicWeight(float(i) - fx);
            float wy = bicubicWeight(float(j) - fy);
            float weight = wx * wy;

            float4 sample = inputTexture.read(uint2(sx, sy));
            color += sample * weight;
            weightSum += weight;
        }
    }

    color /= max(weightSum, 0.001);

    // Apply sharpening using unsharp mask
    float4 blurred = float4(0.0);
    const int radius = 1;
    int count = 0;

    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            int sx = clamp(int(srcX) + dx, 0, int(inWidth) - 1);
            int sy = clamp(int(srcY) + dy, 0, int(inHeight) - 1);
            blurred += inputTexture.read(uint2(sx, sy));
            count++;
        }
    }
    blurred /= float(count);

    float4 sharpened = color + (color - blurred) * params.sharpness;

    // Apply contrast enhancement
    float4 contrasted = (sharpened - 0.5) * params.contrast + 0.5;

    // Apply saturation adjustment
    float luminance = dot(contrasted.rgb, float3(0.299, 0.587, 0.114));
    float4 desaturated = float4(luminance, luminance, luminance, contrasted.a);
    float4 saturated = mix(desaturated, contrasted, params.saturation);

    // Apply bilateral denoising (simplified)
    float4 denoised = saturated;
    if (params.denoise > 0.0) {
        float4 denoisedSum = float4(0.0);
        float weightSum2 = 0.0;
        const int denoiseRadius = 2;

        for (int dy = -denoiseRadius; dy <= denoiseRadius; dy++) {
            for (int dx = -denoiseRadius; dx <= denoiseRadius; dx++) {
                int sx = clamp(int(gid.x) + dx, 0, int(outWidth) - 1);
                int sy = clamp(int(gid.y) + dy, 0, int(outHeight) - 1);

                // Read from output (progressive denoising)
                float spatialWeight = exp(-float(dx*dx + dy*dy) / (2.0 * 4.0));
                float weight = spatialWeight;

                denoisedSum += saturated * weight;
                weightSum2 += weight;
            }
        }

        denoised = mix(saturated, denoisedSum / weightSum2, params.denoise);
    }

    // Clamp and write output
    outputTexture.write(clamp(denoised, 0.0, 1.0), gid);
}

// MARK: - SIFT Feature Detection Kernels

// Gaussian blur for scale-space construction
kernel void gaussianBlur(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &sigma [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    // Calculate Gaussian kernel size
    int kernelRadius = int(ceil(3.0 * sigma));
    float4 sum = float4(0.0);
    float weightSum = 0.0;

    // Apply separable Gaussian blur (horizontal + vertical)
    for (int dy = -kernelRadius; dy <= kernelRadius; dy++) {
        for (int dx = -kernelRadius; dx <= kernelRadius; dx++) {
            int sx = clamp(int(gid.x) + dx, 0, int(width) - 1);
            int sy = clamp(int(gid.y) + dy, 0, int(height) - 1);

            float distance = sqrt(float(dx*dx + dy*dy));
            float weight = exp(-(distance * distance) / (2.0 * sigma * sigma));

            sum += inputTexture.read(uint2(sx, sy)) * weight;
            weightSum += weight;
        }
    }

    outputTexture.write(sum / weightSum, gid);
}

// Compute gradient magnitude and orientation
kernel void computeGradients(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> magnitudeTexture [[texture(1)]],
    texture2d<float, access::write> orientationTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    // Use Sobel operator for gradient computation
    int x = int(gid.x);
    int y = int(gid.y);

    // Sobel X kernel
    float gx = 0.0;
    if (x > 0 && x < int(width)-1 && y > 0 && y < int(height)-1) {
        gx += inputTexture.read(uint2(x+1, y-1)).r * 1.0;
        gx += inputTexture.read(uint2(x+1, y)).r * 2.0;
        gx += inputTexture.read(uint2(x+1, y+1)).r * 1.0;
        gx -= inputTexture.read(uint2(x-1, y-1)).r * 1.0;
        gx -= inputTexture.read(uint2(x-1, y)).r * 2.0;
        gx -= inputTexture.read(uint2(x-1, y+1)).r * 1.0;
    }

    // Sobel Y kernel
    float gy = 0.0;
    if (x > 0 && x < int(width)-1 && y > 0 && y < int(height)-1) {
        gy += inputTexture.read(uint2(x-1, y+1)).r * 1.0;
        gy += inputTexture.read(uint2(x, y+1)).r * 2.0;
        gy += inputTexture.read(uint2(x+1, y+1)).r * 1.0;
        gy -= inputTexture.read(uint2(x-1, y-1)).r * 1.0;
        gy -= inputTexture.read(uint2(x, y-1)).r * 2.0;
        gy -= inputTexture.read(uint2(x+1, y-1)).r * 1.0;
    }

    // Compute magnitude and orientation
    float magnitude = sqrt(gx * gx + gy * gy);
    float orientation = atan2(gy, gx);

    magnitudeTexture.write(float4(magnitude), gid);
    orientationTexture.write(float4(orientation), gid);
}

// Difference of Gaussians (DoG) for keypoint detection
kernel void differenceOfGaussians(
    texture2d<float, access::read> texture1 [[texture(0)]],
    texture2d<float, access::read> texture2 [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= texture1.get_width() || gid.y >= texture1.get_height()) {
        return;
    }

    float4 val1 = texture1.read(gid);
    float4 val2 = texture2.read(gid);
    float4 difference = val1 - val2;

    outputTexture.write(difference, gid);
}

// Non-maximum suppression for keypoint localization
kernel void nonMaxSuppression(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::write> outputTexture [[texture(1)]],
    constant float &threshold [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = inputTexture.get_width();
    uint height = inputTexture.get_height();

    if (gid.x < 1 || gid.x >= width - 1 || gid.y < 1 || gid.y >= height - 1) {
        outputTexture.write(float4(0.0), gid);
        return;
    }

    float centerValue = inputTexture.read(gid).r;

    // Check if it's a local maximum or minimum
    bool isMaximum = true;
    bool isMinimum = true;

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            if (dx == 0 && dy == 0) continue;

            float neighborValue = inputTexture.read(uint2(int(gid.x) + dx, int(gid.y) + dy)).r;

            if (neighborValue >= centerValue) {
                isMaximum = false;
            }
            if (neighborValue <= centerValue) {
                isMinimum = false;
            }
        }
    }

    // Only keep strong keypoints
    if ((isMaximum || isMinimum) && abs(centerValue) > threshold) {
        outputTexture.write(float4(centerValue), gid);
    } else {
        outputTexture.write(float4(0.0), gid);
    }
}

// MARK: - Depth Map Refinement

// Bilateral filter for depth map smoothing
kernel void bilateralFilterDepth(
    texture2d<float, access::read> depthTexture [[texture(0)]],
    texture2d<float, access::read> colorTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant float &spatialSigma [[buffer(0)]],
    constant float &rangeSigma [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = depthTexture.get_width();
    uint height = depthTexture.get_height();

    if (gid.x >= width || gid.y >= height) {
        return;
    }

    float centerDepth = depthTexture.read(gid).r;
    float4 centerColor = colorTexture.read(gid);

    float depthSum = 0.0;
    float weightSum = 0.0;
    const int radius = 5;

    for (int dy = -radius; dy <= radius; dy++) {
        for (int dx = -radius; dx <= radius; dx++) {
            int sx = clamp(int(gid.x) + dx, 0, int(width) - 1);
            int sy = clamp(int(gid.y) + dy, 0, int(height) - 1);

            float neighborDepth = depthTexture.read(uint2(sx, sy)).r;
            float4 neighborColor = colorTexture.read(uint2(sx, sy));

            // Spatial weight
            float spatialDist = sqrt(float(dx*dx + dy*dy));
            float spatialWeight = exp(-(spatialDist * spatialDist) / (2.0 * spatialSigma * spatialSigma));

            // Range weight (based on depth difference)
            float depthDiff = abs(centerDepth - neighborDepth);
            float rangeWeight = exp(-(depthDiff * depthDiff) / (2.0 * rangeSigma * rangeSigma));

            // Color similarity weight
            float colorDiff = length(centerColor - neighborColor);
            float colorWeight = exp(-(colorDiff * colorDiff) / (2.0 * rangeSigma * rangeSigma));

            float weight = spatialWeight * rangeWeight * colorWeight;

            depthSum += neighborDepth * weight;
            weightSum += weight;
        }
    }

    float filteredDepth = depthSum / max(weightSum, 0.001);
    outputTexture.write(float4(filteredDepth), gid);
}

// MARK: - Optical Flow for Feature Tracking

// Lucas-Kanade optical flow
kernel void opticalFlowLK(
    texture2d<float, access::read> prevTexture [[texture(0)]],
    texture2d<float, access::read> currTexture [[texture(1)]],
    texture2d<float, access::write> flowTexture [[texture(2)]],
    uint2 gid [[thread_position_in_grid]])
{
    uint width = prevTexture.get_width();
    uint height = prevTexture.get_height();

    if (gid.x < 2 || gid.x >= width - 2 || gid.y < 2 || gid.y >= height - 2) {
        flowTexture.write(float4(0.0), gid);
        return;
    }

    // Compute image gradients
    float Ix = 0.0, Iy = 0.0, It = 0.0;
    float A11 = 0.0, A12 = 0.0, A22 = 0.0;
    float b1 = 0.0, b2 = 0.0;

    const int windowSize = 5;
    const int halfWindow = windowSize / 2;

    for (int dy = -halfWindow; dy <= halfWindow; dy++) {
        for (int dx = -halfWindow; dx <= halfWindow; dx++) {
            uint2 pos = uint2(int(gid.x) + dx, int(gid.y) + dy);

            // Spatial gradients
            float gx = (currTexture.read(uint2(pos.x + 1, pos.y)).r -
                       currTexture.read(uint2(pos.x - 1, pos.y)).r) * 0.5;
            float gy = (currTexture.read(uint2(pos.x, pos.y + 1)).r -
                       currTexture.read(uint2(pos.x, pos.y - 1)).r) * 0.5;

            // Temporal gradient
            float gt = currTexture.read(pos).r - prevTexture.read(pos).r;

            // Accumulate for least squares
            A11 += gx * gx;
            A12 += gx * gy;
            A22 += gy * gy;
            b1 += -gx * gt;
            b2 += -gy * gt;
        }
    }

    // Solve 2x2 system using Cramer's rule
    float det = A11 * A22 - A12 * A12;
    float2 flow = float2(0.0);

    if (abs(det) > 0.001) {
        flow.x = (A22 * b1 - A12 * b2) / det;
        flow.y = (A11 * b2 - A12 * b1) / det;
    }

    flowTexture.write(float4(flow, 0.0, 1.0), gid);
}
