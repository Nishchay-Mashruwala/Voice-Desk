/// Every model the phone can download: where from, exact sizes and SHA-256,
/// and where each lives under `<models root>/speech/`.
library;

/// A file to download, with its exact size and SHA-256.
class ModelDownload {
  const ModelDownload(this.url, this.size, this.sha256);
  final Uri url;
  final int size;
  final String sha256;
}

/// A file kept from a downloaded archive.
class ModelMember {
  const ModelMember(this.inArchive, this.fileName, this.size, this.sha256);
  final String inArchive;
  final String fileName;
  final int size;
  final String sha256;
}

enum ModelId { vad, englishFaster, englishAccurate, indicTokens, gujarati, hindi, speakers, taskFaster, taskAccurate }

/// One model: an archive whose [members] are kept in [folder], or a single
/// file saved as `<folder>/<fileName>`.
class ModelSpec {
  const ModelSpec({
    required this.id,
    required this.folder,
    required this.download,
    this.members = const [],
    this.fileName,
    this.needs = const [],
  }) : assert(members.length > 0 || fileName != null);

  final ModelId id;

  /// Under `speech/`; empty for `speech/` itself.
  final String folder;
  final ModelDownload download;
  final List<ModelMember> members;
  final String? fileName;

  /// Models this one can't work without (downloaded first, kept while used).
  final List<ModelId> needs;

  bool get isArchive => members.isNotEmpty;

  /// The names of the files it leaves on the phone.
  List<String> get fileNames => isArchive ? [for (final m in members) m.fileName] : [fileName!];
}

/// Free storage needed to start: an archive needs room for itself, the
/// unpacked tar and the files; a single file for itself and a margin.
int minFreeToDownload(ModelSpec s) => s.isArchive ? 3 * s.download.size : s.download.size + 100 * 1024 * 1024;

const _sherpa = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';
/// The desktop's task models (desktop/backend/core/src/downloads.rs), pinned to a commit.
const _qwen = 'https://huggingface.co/unsloth';
const _indic =
    'https://huggingface.co/parismitaglobalsolutions/indicconformer-sherpa-onnx/resolve/9721eb71eea141fae0982cfcdb9dd2e3d4953c4a';

final kCatalogue = <ModelId, ModelSpec>{
  ModelId.vad: ModelSpec(
    id: ModelId.vad,
    folder: '',
    fileName: 'silero_vad.onnx',
    download: ModelDownload(
        Uri.parse('$_sherpa/silero_vad.onnx'), 643854, '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6'),
  ),
  ModelId.englishFaster: ModelSpec(
    id: ModelId.englishFaster,
    folder: 'parakeet-tdt-110m',
    download: ModelDownload(Uri.parse('$_sherpa/sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8.tar.bz2'), 108035095,
        'f628312e9fdf8686374cb01a69425c41732529d540860311f16f37cbc32cfe9b'),
    members: const [
      ModelMember('sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/encoder.int8.onnx', 'encoder.int8.onnx',
          131113202, '0f35509ddeb9b39002fb077d979a9fe74f06eb0bc4dd5c34f512f82e5111d657'),
      ModelMember('sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/decoder.int8.onnx', 'decoder.int8.onnx',
          3955863, 'f7c331c5504c2e593c76ed22b728e3f554af6c4a383dde862e719ced08b1da19'),
      ModelMember('sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/joiner.int8.onnx', 'joiner.int8.onnx', 1411403,
          'bf7dff69e9f2cdbe9943d70da358f38b361c115ba0105bae7e908e0d6ec782f6'),
      ModelMember('sherpa-onnx-nemo-parakeet_tdt_transducer_110m-en-36000-int8/tokens.txt', 'tokens.txt', 9953,
          '450e56bd2f036fe5b6aa821865838cc5aa9d8b0106134ce9a9ba0664abe6cd10'),
    ],
  ),
  ModelId.englishAccurate: ModelSpec(
    id: ModelId.englishAccurate,
    folder: 'parakeet-tdt-0.6b',
    download: ModelDownload(Uri.parse('$_sherpa/sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8.tar.bz2'), 482468385,
        '157c157bc51155e03e37d2466522a3a737dd9c72bb25f36eb18912964161e1ad'),
    members: const [
      ModelMember('sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/encoder.int8.onnx', 'encoder.int8.onnx', 652184296,
          'a32b12d17bbbc309d0686fbbcc2987b5e9b8333a7da83fa6b089f0a2acd651ab'),
      ModelMember('sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/decoder.int8.onnx', 'decoder.int8.onnx', 7257753,
          'b6bb64963457237b900e496ee9994b59294526439fbcc1fecf705b31a15c6b4e'),
      ModelMember('sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/joiner.int8.onnx', 'joiner.int8.onnx', 1739080,
          '7946164367946e7f9f29a122407c3252b680dbae9a51343eb2488d057c3c43d2'),
      ModelMember('sherpa-onnx-nemo-parakeet-tdt-0.6b-v2-int8/tokens.txt', 'tokens.txt', 9384, 'ec182b70dd42113aff6c5372c75cac58c952443eb22322f57bbd7f53977d497d'),
    ],
  ),
  ModelId.indicTokens: ModelSpec(
    id: ModelId.indicTokens,
    folder: 'indic',
    fileName: 'tokens.txt',
    download: ModelDownload(
        Uri.parse('$_indic/tokens.txt'), 67605, 'ee60967630213f31951817ac8b402b92ec18cce80718a24a49b388e56672dfb2'),
  ),
  ModelId.gujarati: ModelSpec(
    id: ModelId.gujarati,
    folder: 'indic',
    fileName: 'gu.int8.onnx',
    needs: const [ModelId.indicTokens],
    download: ModelDownload(Uri.parse('$_indic/gu/model.int8.onnx'), 197595461,
        '822ed7f0b809bbd479275bf91c913d05564b88c0d082bbcba2f37999b88cb598'),
  ),
  ModelId.speakers: ModelSpec(
    id: ModelId.speakers,
    folder: 'speakers',
    fileName: 'campplus.onnx',
    // 3D-Speaker's CAM++ (Chinese + English), 192-number voice prints; it told
    // two voices and the owner's voice apart best (Plan 3's measurements).
    download: ModelDownload(
        Uri.parse('https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/'
            '3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced.onnx'),
        28281164,
        'aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2'),
  ),
  ModelId.hindi: ModelSpec(
    id: ModelId.hindi,
    folder: 'indic',
    fileName: 'hi.int8.onnx',
    needs: const [ModelId.indicTokens],
    download: ModelDownload(Uri.parse('$_indic/hi/model.int8.onnx'), 197595593,
        '915c71e04dd7e5378a4057fdebb252b3a587188e4e99db6d7ce0909ad5ad05fa'),
  ),
  // The task AI: Qwen3 1.7B on every phone; 4B ("More accurate") on phones
  // with 8 GB (lib/engine/tasks/task_settings.dart).
  ModelId.taskFaster: ModelSpec(
    id: ModelId.taskFaster,
    folder: 'tasks',
    fileName: 'Qwen3-1.7B-Q4_K_M.gguf',
    download: ModelDownload(Uri.parse('$_qwen/Qwen3-1.7B-GGUF/resolve/d7f544eead698dbd1f15126ef60b45a1e1933222/Qwen3-1.7B-Q4_K_M.gguf'),
        1107409472, 'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897'),
  ),
  ModelId.taskAccurate: ModelSpec(
    id: ModelId.taskAccurate,
    folder: 'tasks',
    fileName: 'Qwen3-4B-Q4_K_M.gguf',
    download: ModelDownload(Uri.parse('$_qwen/Qwen3-4B-GGUF/resolve/22c9fc8a8c7700b76a1789366280a6a5a1ad1120/Qwen3-4B-Q4_K_M.gguf'),
        2497281312, 'f6f851777709861056efcdad3af01da38b31223a3ba26e61a4f8bf3a2195813a'),
  ),
};
