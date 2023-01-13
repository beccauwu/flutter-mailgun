import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class MailgunOptions {
  Map<String, dynamic>? templateVariables;
  @override
  String toString() {
    return jsonEncode(templateVariables);
  }
}

enum ContentType { html, text, template }

enum MGResponseStatus { SUCCESS, FAIL, QUEUED }

class MGResponse {
  MGResponseStatus status;
  String message;

  MGResponse(this.status, this.message);
}

class Content {
  ContentType type;
  String value;

  Content(this.type, this.value);
}

class MailgunSender {
  final String domain;
  final String apiKey;
  final bool regionIsEU;

  MailgunSender(
      {required this.domain, required this.apiKey, this.regionIsEU = false});

  Future<MGResponse> send(
      {String from = 'mailgun',
      required List<String> to,
      List<String>? cc,
      List<String>? bcc,
      List<dynamic> attachments = const [],
      required String subject,
      required Content content,
      MailgunOptions? options,
      bool? useDifferentFromDomain}) async {
    var client = http.Client();
    var host = regionIsEU ? 'api.eu.mailgun.net' : 'api.mailgun.net';
    try {
      var request = http.MultipartRequest(
          'POST',
          Uri(
              userInfo: 'api:$apiKey',
              scheme: 'https',
              host: host,
              path: '/v3/$domain/messages'));
      request.fields['subject'] = subject;
      request.fields['from'] = from;
      request.fields['cc'] = cc?.join(", ") ?? '';
      request.fields['bcc'] = bcc?.join(", ") ?? '';
      switch (content.type) {
        case ContentType.html:
          request.fields['html'] = content.value;
          break;
        case ContentType.text:
          request.fields['text'] = content.value;
          break;
        case ContentType.template:
          request.fields['template'] = content.value;
          request.fields['h:X-Mailgun-Variables'] = options.toString();
          break;
        default:
          throw Exception('Unknown content type');
      }

      if (to.length > 0) {
        request.fields['to'] = to.join(", ");
      }
      if (options != null) {
        if (options.templateVariables != null) {
          request.fields['h:X-Mailgun-Variables'] =
              jsonEncode(options.templateVariables);
        }
      }
      if (attachments.length > 0) {
        request.headers["Content-Type"] = "multipart/form-data";
        for (var i = 0; i < attachments.length; i++) {
          var attachment = attachments[i];
          if (attachment is File) {
            request.files.add(await http.MultipartFile.fromPath(
                'attachment', attachment.path));
          }
        }
      }
      var response = await client.send(request);
      var responseBody = await response.stream.bytesToString();
      var jsonBody = jsonDecode(responseBody);
      var message = jsonBody['message'] ?? '';
      if (response.statusCode != HttpStatus.ok) {
        return MGResponse(MGResponseStatus.FAIL, message);
      }

      return MGResponse(MGResponseStatus.SUCCESS, message);
    } catch (e) {
      return MGResponse(MGResponseStatus.FAIL, e.toString());
    } finally {
      client.close();
    }
  }
}
