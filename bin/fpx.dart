import 'dart:io';
import 'package:fpx_cli/fpx_cli.dart';

void main(List<String> args) async {
  final cli = FpxCli();
  final exitCode = await cli.run(args);
  exit(exitCode);
}
