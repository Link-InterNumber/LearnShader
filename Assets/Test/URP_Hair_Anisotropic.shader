Shader "Custom/URP_Hair_Anisotropic"
{
    Properties
    {
        _BaseMap ("Hair Texture", 2D) = "white" {}
        _BaseColor ("Hair Color", Color) = (0.3,0.2,0.1,1)
        _NormalMap ("Normal Map", 2D) = "bump" {}
        
        [Header(Hair Anisotropic)]
        _PrimaryShift ("Primary Shift", Range(-1, 1)) = 0.1
        _SecondaryShift ("Secondary Shift", Range(-1, 1)) = -0.1
        _PrimarySpecular ("Primary Specular", Range(0, 5)) = 2.0
        _SecondarySpecular ("Secondary Specular", Range(0, 5)) = 1.0
        _PrimaryRoughness ("Primary Roughness", Range(0.01, 1)) = 0.1
        _SecondaryRoughness ("Secondary Roughness", Range(0.01, 1)) = 0.3
        
        [Header(Colors)]
        _PrimarySpecColor ("Primary Spec Color", Color) = (1,1,1,1)
        _SecondarySpecColor ("Secondary Spec Color", Color) = (1,0.8,0.6,1)
        
        [Header(Transparency)]
        _Alpha ("Alpha", Range(0, 1)) = 1.0
        _AlphaClip ("Alpha Clip", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags 
        { 
            "RenderType"="TransparentCutout" 
            "Queue"="AlphaTest"
            "RenderPipeline"="UniversalPipeline" 
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            
            Cull Off
            AlphaToMask On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS

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

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BaseColor;
                float _PrimaryShift;
                float _SecondaryShift;
                float _PrimarySpecular;
                float _SecondarySpecular;
                float _PrimaryRoughness;
                float _SecondaryRoughness;
                float4 _PrimarySpecColor;
                float4 _SecondarySpecColor;
                float _Alpha;
                float _AlphaClip;
            CBUFFER_END

            // 头发高光计算
            float HairSpecular(float TdotH, float roughness)
            {
                float sinTH = sqrt(1.0 - TdotH * TdotH);
                float dirAtten = smoothstep(-1.0, 0.0, TdotH);
                return dirAtten * pow(sinTH, 1.0 / roughness);
            }

            // 头发移位
            float3 ShiftTangent(float3 T, float3 N, float shift)
            {
                float3 shiftedT = T + shift * N;
                return normalize(shiftedT);
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
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                // 采样纹理
                half4 baseMap = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv);
                half3 albedo = baseMap.rgb * _BaseColor.rgb;
                half alpha = baseMap.a * _BaseColor.a * _Alpha;
                
                // Alpha测试
                clip(alpha - _AlphaClip);
                
                // 法线
                half3 normalWS = normalize(input.normalWS);
                half3 tangentWS = normalize(input.tangentWS);
                half3 bitangentWS = normalize(input.bitangentWS);
                
                // 光照计算
                Light mainLight = GetMainLight();
                half3 lightDir = normalize(mainLight.direction);
                half3 viewDir = normalize(GetWorldSpaceViewDir(input.positionWS));
                half3 halfDir = normalize(lightDir + viewDir);
                
                // 头发切线方向
                half3 T1 = ShiftTangent(tangentWS, normalWS, _PrimaryShift);
                half3 T2 = ShiftTangent(tangentWS, normalWS, _SecondaryShift);
                
                // 计算两层高光
                float TdotH1 = dot(T1, halfDir);
                float TdotH2 = dot(T2, halfDir);
                
                float spec1 = HairSpecular(TdotH1, _PrimaryRoughness) * _PrimarySpecular;
                float spec2 = HairSpecular(TdotH2, _SecondaryRoughness) * _SecondarySpecular;
                
                half3 specular1 = spec1 * _PrimarySpecColor.rgb;
                half3 specular2 = spec2 * _SecondarySpecColor.rgb;
                
                // 漫反射
                half NdotL = saturate(dot(normalWS, lightDir));
                half3 diffuse = albedo * NdotL;
                
                // 组合最终颜色
                half3 finalColor = diffuse + specular1 + specular2;
                finalColor *= mainLight.color;
                finalColor += albedo * 0.1; // 环境光
                
                return half4(finalColor, alpha);
            }
            ENDHLSL
        }
    }
}