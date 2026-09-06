# 해무급 전열 순양함 — 품질 기준 자산 v1

## 목적

해무급은 상세 항행 화면의 첫 영웅 자산이다. 특정 작품의 함선을 복제하지 않고, 사람 세력의 산업적 장거리 우주 해군이라는 시각 언어를 세운다. 이 문서는 전열함 한 척의 디자인·모델링·게임 화면 검토를 같은 완료 기준으로 묶는다.

콘셉트 기준: [`haemu-line-battleship-v1.png`](../../assets/concepts/haemu-line-battleship-v1.png)

## 디자인 결정

- 역할: 240m급 전열 순양함. 선도·호위·전방 화력 투사를 담당한다.
- 실루엣: 비대칭 5면 방패형 선체, 낮은 전방 센서 쐐기, 계단식 장갑 척추, 4개로 분리된 선미 엔진 boom.
- 기능 구조: 전방 센서/방열 구획, 중앙 장갑 용골, 양현 포곽과 유도탄 셀, 우현 센서·드론 회수면, 선미 자세제어 노즐.
- 재질: 청회색 세라믹 금속, 무광 방열판, 국소적 열 변색과 정비 마킹, 청백색 엔진 코어와 절제된 호박색 항법등.

## 금지선

- 평면 삼각 쐐기, 중앙 아일랜드 지휘탑, 구형 함교 돔, 특정 프랜차이즈 문장·색 조합을 사용하지 않는다.
- Star Wars, Halo, Homeworld, Infinite Lagrange의 개별 실루엣·부품 배치·텍스처·UI 구도를 복제하지 않는다.
- 전 표면에 균일한 greeble 또는 균일한 발광을 적용하지 않는다.

## 제작 전달물

1. 정면·측면·상면·하면·후면 orthographic sheet와 기능 콜아웃.
2. `line_ship_lod0.glb`부터 `line_ship_lod3.glb`까지의 GLB.
3. `basecolor`, `normal`, `ORM`, `emissive` PBR 세트.
4. 엔진 플룸, 자세 제어 펄스, 열 왜곡용 VFX.
5. 140척 항행 검수 컷: 전방 3/4, 측후방, 함선 사이 카메라, 360° 회전, 1x/16x/64x 배경 항행.

## LOD·성능 기준

| 등급 | 삼각형 | 동시 수 | 역할 |
| --- | ---: | ---: | --- |
| LOD0 | 70k–100k | 2–6 | 카메라 근접 영웅 함선 |
| LOD1 | 20k–30k | 18 | 근거리 편대 |
| LOD2 | 3k–6k | 48 | 중거리 편대 |
| LOD3 | 300–800 / impostor | 나머지 | 원거리 군집 |

140척 상세 항행에서 60fps(p95 16.67ms), 3D GPU 9ms 이하, CPU 5ms 이하를 목표로 한다. 원거리 군집은 `MultiMeshInstance3D` 구역 배치로 처리하며, 실제 함종 비율과 진형을 유지한다.

## 품질 게이트

1. **실루엣 리뷰:** 엔진을 끈 상태에서도 전후 방향·함급·사람 세력 소속이 2초 안에 읽힌다.
2. **PBR 리뷰:** 근접 360° 관측에서 패널, 거칠기, 노멀, 엔진 노즐이 물리적으로 설득력 있게 반응한다.
3. **항행 리뷰:** 함대는 정본 진형으로 고정되고, 별·성운·파편 배경만 시간 배속에 비례해 항행감을 만든다.
4. **대군 리뷰:** 가까운 영웅함·중거리 호위함·원거리 군집이 같은 함대의 계층으로 읽힌다.
5. **성능 리뷰:** 50/140/300/500척, 모든 진형, 360° 줌에서 LOD 튐·프레임 드롭·메모리 급증이 없다.

## 기술 전제

실사형 품질 프리셋은 Godot Forward+를 기준으로 HDR, Filmic tone mapping, 제한적 glow, Sky radiance, AO를 사용한다. Compatibility 렌더러는 전략 화면 및 간략 상세 화면의 fallback으로 유지한다. Forward+ 전환은 프로젝트 기본 렌더러를 바로 바꾸지 않고, 목표 GPU에서 품질·성능을 먼저 검증한 뒤 결정한다.

## 참고 원칙

- [Homeworld 3 공식 소개](https://www.blackbirdinteractive.com/homeworld3): 3D 함대·스케일·공간 지형의 관계.
- [Infinite Lagrange 기함 편성 소개](https://www.neteasegames.com/news/game/20221205/30576_1056229.html): 기함과 편대 역할의 관계.
- [Halo 함선 개발 사례](https://www.halowaypoint.com/news/canon-fodder-digsite-dissection): 역할에서 실루엣을 도출하는 방법.
- [Godot Environment / post-processing 문서](https://docs.godotengine.org/en/4.7/tutorials/3d/environment_and_post_processing.html): 품질 프리셋의 기술 근거.
