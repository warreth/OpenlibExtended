// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

// Package imports:
import 'package:url_launcher/url_launcher.dart';
import 'package:yaml/yaml.dart';

// Project imports:
import 'package:openlib/ui/components/page_title_widget.dart';
import 'package:openlib/ui/components/snack_bar_widget.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = 'Loading...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final yamlString = await rootBundle.loadString('pubspec.yaml');
      final yamlMap = loadYaml(yamlString);
      final version = yamlMap['version'] as String;
      setState(() {
        _version = version;
      });
    } catch (e) {
      setState(() {
        _version = 'Unknown';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text("OpenlibExtended"),
        titleTextStyle: Theme.of(context).textTheme.displayLarge,
      ),
      body: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: Padding(
          padding: const EdgeInsets.only(left: 5, right: 5, top: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TitleText("About"),
              const Padding(
                padding:
                    EdgeInsets.only(left: 7, right: 7, top: 13, bottom: 10),
                child: Text(
                  "An Open source app to download and read books from shadow library (Anna's Archive).",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 7, top: 10),
                child: Text(
                  "This is a forked version maintained by warreth for personal use and community updates.",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 7, top: 5),
                child: Text(
                  "Original app by dstark5 (https://github.com/dstark5/Openlib).",
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      color: Colors.grey),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  "Version",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 7, right: 7, top: 5),
                child: Text(
                  _version,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  "Github",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              const _UrlText(
                  text: 'This Fork (by warreth)',
                  url: 'https://github.com/warreth/OpenlibExtended'),
              const _UrlText(
                  text: 'Report An Issue',
                  url: 'https://github.com/warreth/OpenlibExtended/issues'),
              const _UrlText(
                  text: 'Original Project (by dstark5)',
                  url: 'https://github.com/dstark5/Openlib'),
              const Padding(
                padding: EdgeInsets.only(left: 7, right: 7, top: 15),
                child: Text(
                  "Licence",
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
              ),
              const _UrlText(
                  text: "GPL v3.0 license",
                  url: 'https://www.gnu.org/licenses/gpl-3.0.en.html'),
            ],
          ),
        ),
      ),
    );
  }
}

class _UrlText extends StatelessWidget {
  const _UrlText({required this.text, required this.url});

  final String url;
  final String text;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 7, right: 7, top: 5),
      child: InkWell(
        onTap: () async {
          final Uri uri = Uri.parse(url);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            // ignore: use_build_context_synchronously
            showSnackBar(context: context, message: 'Could not launch $uri');
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              text,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(
              width: 2,
            ),
            const Icon(
              Icons.launch,
              size: 17,
              color: Colors.blueAccent,
            )
          ],
        ),
      ),
    );
  }
}
