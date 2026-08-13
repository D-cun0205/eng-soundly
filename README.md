# EngSoundly

한국인 영어 학습자를 위한 발음 진단 iOS 앱.
사용자의 발음을 듣고 **실제로 낸 소리(IPA)** 를 인식해, 미국 영어 원어민 발음과의
차이를 한국어 화자 특유의 간섭 패턴(L1 interference) 관점에서 설명하고 교정법을 제시한다.

## 파이프라인

```
녹음 (16kHz mono)
  → 음소 인식 (wav2vec2 phoneme CTC, Core ML, 온디바이스)
  → 목표 발음 (CMUdict ARPAbet → canonical IPA)
  → 정렬 (Needleman–Wunsch, 음성학적 자질 기반 비용)
  → 한국인 L1 규칙 매칭 (r/l, f/p, θ/s, 모음 삽입 등 15종)
  → 한국어 설명 + 조음 교정 팁 + 원어민 TTS 대조
```

핵심 설계: 일반 음성인식(ASR)은 문맥 보정 때문에 "말하려던 단어"를 돌려주므로 쓸 수 없다.
음소 CTC 모델은 "실제로 낸 소리"를 IPA로 출력하므로 발음 진단이 가능하다.
판정은 규칙 기반(결정적), 설명은 사전 작성된 한국어 규칙 카드가 담당한다.

## 구조

| 경로 | 역할 |
|---|---|
| `Sources/Models/PhonemeMapping.swift` | 표준 음소 집합, ARPAbet→IPA, espeak 정규화, 자질 테이블 |
| `Sources/Diagnosis/PhonemeAligner.swift` | 자질 비용 기반 전역 정렬 |
| `Sources/Diagnosis/KoreanL1Rules.swift` | 한국인 간섭 패턴 규칙 15종 (한국어 설명 포함) |
| `Sources/Diagnosis/DiagnosisEngine.swift` | 변이형 선택, 이슈 생성, 점수 계산 |
| `Sources/Services/PhonemeRecognizer.swift` | Core ML CTC 인식기 + 데모용 목 |
| `Sources/Services/AudioRecorder.swift` | AVAudioEngine 16kHz 캡처, 무음 트리밍 |
| `Sources/Services/PronunciationDictionary.swift` | CMUdict 로더 (13.5만 단어) |
| `Resources/words.json` | 카테고리별 연습 단어 (최소대립쌍 포함) |
| `Tools/convert_model.py` | wav2vec2-lv-60-espeak-cv-ft → Core ML 변환 |

## 빌드

```bash
xcodegen generate
xcodebuild -project EngSoundly.xcodeproj -target EngSoundly -sdk iphonesimulator build
```

## 음향 모델

번들에 `PhonemeCTC.mlpackage` + `phoneme_vocab.json`이 없으면 **데모 모드**로 동작한다
(전형적 한국인 오류를 주입한 예시 진단 표시).

실제 모델 생성:

```bash
cd Tools
/opt/homebrew/opt/python@3.11/bin/python3.11 -m venv venv
./venv/bin/pip install torch transformers coremltools numpy
./venv/bin/python convert_model.py   # → Resources/PhonemeCTC.mlpackage (~630MB fp16)
xcodegen generate && rebuild
```

모델: [facebook/wav2vec2-lv-60-espeak-cv-ft](https://huggingface.co/facebook/wav2vec2-lv-60-espeak-cv-ft)
(다국어 음소 인식, espeak IPA 출력). 배포 시 int8 양자화로 ~320MB까지 축소 가능.

## 로드맵

1. ✅ 단어 단위 MVP (음소 진단 + 규칙 카드 + TTS 대조)
2. 문장 단위 — 연음 변이형 생성·정렬, 강세/리듬 분석
3. 개인화 — 음소별 오류율 추적, 취약 음소 드릴
