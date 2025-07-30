Shader "Custom/Chapter8/Chapter8-AlphaBlend"
{
   Properties
   {
      _Color ("Color", Color) = (1, 1, 1, 1)
      _MainTex ("Main Tex", 2D) = "white" {}
      _AlphaSacle ("Alpha Sacle", Range(0.0, 1.0)) = 1.0
   }
   SubShader
   {
      LOD 300
      Tags { "Queue" = "Transparent" "IgnoreProjector" = "True" "RenderType" = "Transparent" }
      Pass
      {
         Name "ForwardLit"
         Tags
         {
            "LightMode" = "UniversalForward"
         }
         ZWrite Off
         Blend SrcAlpha OneMinusSrcAlpha

         CGPROGRAM

         #pragma vertex vert
         #pragma fragment frag

         #include "Lighting.cginc"
         #include "UnityCG.cginc"

         fixed4 _Color;
         sampler2D _MainTex;
         float4 _MainTex_ST;
         float _AlphaSacle;

         struct a2v
         {
            float4 vertex : POSITION;
            float3 normal : NORMAL;
            float2 texcoord : TEXCOORD0;
         };

         struct v2f
         {
            float4 pos : SV_POSITION;
            float3 worldNormal : TEXCOORD0;
            fixed3 worldPos : TEXCOORD1;
            float2 uv : TEXCOORD2;
         };

         v2f vert(a2v v)
         {
            v2f o;
            o.pos = UnityObjectToClipPos(v.vertex);
            o.worldNormal = UnityObjectToWorldNormal(v.normal);
            o.worldPos = mul(unity_ObjectToWorld, v.vertex);
            o.uv = v.texcoord * _MainTex_ST.xy + _MainTex_ST.zw; // Adjust UVs based on texture scale and offset
            o.uv = TRANSFORM_TEX(v.texcoord, _MainTex); // Use Unity's macro to handle texture transformations
            return o;
         }

         fixed4 frag(v2f i) : SV_Target
         {
            fixed3 worldNormal = normalize(i.worldNormal);
            fixed3 worldLightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));

            fixed4 texColor = tex2D(_MainTex, i.uv);

            fixed3 albedo = texColor.rgb * _Color.rgb;
            fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz * albedo;
            fixed3 diffuse = _LightColor0.rgb * albedo * saturate(dot(worldNormal, worldLightDir));
            return fixed4(ambient + diffuse, texColor.a * _AlphaSacle);
         }
         ENDCG
      }
   }
   FallBack "Transparent/VertexLit" // Use a fallback shader that supports alpha testing
}