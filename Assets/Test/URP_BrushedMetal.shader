Shader "Custom/URP_BrushedMetal"
{
    Properties
    {
        _BaseColor ("Metal Color", Color) = (0.8,0.8,0.8,1)
        _MetallicMap ("Metallic Map", 2D) = "white" {}
        _RoughnessMap ("Roughness Map", 2D) = "white" {}
        _NormalMap ("Normal Map", 2D) = "bump" {}
        
        [Header(Anisotropic Settings)]
        _AnisotropyStrength ("Anisotropy Strength", Range(0, 1)) = 0.8
        _BrushDirection ("Brush Direction", Vector) = (1,0,0,0)
        _RoughnessU ("Roughness U", Range(0.01, 1)) = 0.02
        _RoughnessV ("Roughness V", Range(0.01, 1)) = 0.8
        
        [Header(Environment)]
        _ReflectionIntensity ("Reflection Intensity", Range(0, 2)) = 1.0
    }

    SubShader
    {
        Tags 
        { 
            "RenderType"="Opaque" 
            "RenderPipeline"="UniversalPipeline" 
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile _ _REFLECTION_PROBE_BOX_PROJECTION

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 tangentWS : TEXCOORD3;
                float3 bitangentWS : TEXCOORD4;
            };

            TEXTURE2D(_MetallicMap);
            SAMPLER(sampler_MetallicMap);
            TEXTURE2D(_RoughnessMap);
            SAMPLER(sampler_RoughnessMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _BrushDirection;
                float _AnisotropyStrength;
                float _RoughnessU;
                float _RoughnessV;
                float _ReflectionIntensity;
            CBUFFER_END

            // GGX各向异性分布
            float D_GGX_Anisotropic(float NdotH, float HdotX, float HdotY, float ax, float ay)
            {
                float a2 = ax * ay;
                float3 v = float3(ay * HdotX, ax * HdotY, a2 * NdotH);
                float v2 = dot(v, v);
                float w2 = a2 / v2;
                return a2 * w2 * w2 / PI;
            }

            // Smith几何函数（各向异性）
            float G_SmithAnisotropic(float NdotV, float NdotL, float VdotX, float VdotY, float LdotX, float LdotY, float ax, float ay)
            {
                float lambdaV = NdotL * sqrt(ax * ax * VdotX * VdotX + ay * ay * VdotY * VdotY + NdotV * NdotV);
                float lambdaL = NdotV * sqrt(ax * ax * LdotX * LdotX + ay * ay * LdotY * LdotY + NdotL * NdotL);
                return 0.5 / (lambdaV + lambdaL);
            }

            Varyings vert(Attributes input)
            {
                Varyings output;
                
                VertexPositionInputs positionInputs = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInputs = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                
                output.positionCS = positionInputs.positionCS;
                output.positionWS = positionInputs.positionWS;
                output.normalWS = normalInputs.normalWS;
                output.tangentWS = normalInputs.tangentWS;
                output.bitangentWS = normalInputs.bitangentWS;
                output.uv = input.uv;
                
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // 采样材质贴图
                half metallic = SAMPLE_TEXTURE2D(_MetallicMap, sampler_MetallicMap, input.uv).r;
                half roughnessMap = SAMPLE_TEXTURE2D(_RoughnessMap, sampler_RoughnessMap, input.uv).r;
                
                // 构建TBN
                half3 normalWS = normalize(input.normalWS);
                half3 tangentWS = normalize(input.tangentWS);
                half3 bitangentWS = normalize(input.bitangentWS);
                
                // 调整拉丝方向
                half3 anisotropicX = normalize(tangentWS + _BrushDirection.xyz * _BrushDirection.w);
                half3 anisotropicY = normalize(cross(normalWS, anisotropicX));
                
                // 光照向量
                Light mainLight = GetMainLight();
                half3 L = normalize(mainLight.direction);
                half3 V = normalize(GetWorldSpaceViewDir(input.positionWS));
                half3 H = normalize(L + V);
                
                // 点积计算
                float NdotH = saturate(dot(normalWS, H));
                float NdotV = saturate(dot(normalWS, V));
                float NdotL = saturate(dot(normalWS, L));
                float VdotH = saturate(dot(V, H));
                
                float HdotX = dot(H, anisotropicX);
                float HdotY = dot(H, anisotropicY);
                float VdotX = dot(V, anisotropicX);
                float VdotY = dot(V, anisotropicY);
                float LdotX = dot(L, anisotropicX);
                float LdotY = dot(L, anisotropicY);
                
                // 各向异性粗糙度
                float ax = max(0.001, _RoughnessU * roughnessMap);
                float ay = max(0.001, _RoughnessV * roughnessMap);
                
                // BRDF计算
                float D = D_GGX_Anisotropic(NdotH, HdotX, HdotY, ax, ay);
                float G = G_SmithAnisotropic(NdotV, NdotL, VdotX, VdotY, LdotX, LdotY, ax, ay);
                
                // Fresnel
                half3 F0 = lerp(0.04, _BaseColor.rgb, metallic);
                half3 F = F0 + (1.0 - F0) * pow(1.0 - VdotH, 5.0);
                
                // 镜面反射
                half3 specular = D * G * F / (4.0 * NdotV * NdotL + 0.001);
                
                // 漫反射
                half3 diffuse = _BaseColor.rgb * (1.0 - metallic) * (1.0 - F);
                
                // 环境反射
                half3 reflectVector = reflect(-V, normalWS);
                half3 envReflection = GlossyEnvironmentReflection(reflectVector, 
                    lerp(_RoughnessU, _RoughnessV, 0.5) * roughnessMap, 1.0);
                envReflection *= F * _ReflectionIntensity * metallic;
                
                // 最终颜色
                half3 finalColor = (diffuse + specular) * mainLight.color * NdotL + envReflection;
                finalColor += _BaseColor.rgb * 0.03; // 环境光
                
                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}