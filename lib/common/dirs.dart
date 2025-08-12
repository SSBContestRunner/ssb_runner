import 'package:path_provider/path_provider.dart';

const dirLog = 'log';
const dirDb = 'db';

Future<String> getAppDirectory() async {
  final directory = await getApplicationDocumentsDirectory();
  return '${directory.path}/ssb_runner';
}
