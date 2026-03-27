import 'package:convert/convert.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:s3_dart/minio.dart';
import 'package:s3_dart/src/minio_client.dart';
import 'package:s3_dart/src/minio_helpers.dart';
import 'package:s3_dart/src/utils.dart';

const signV4Algorithm = 'AWS4-HMAC-SHA256';

String signV4(
  Minio minio,
  MinioRequest request,
  DateTime requestDate,
  String region,
) {
  final signedHeaders = getSignedHeaders(request.headers.keys);
  final hashedPayload =
      request.headers['x-amz-content-sha256'] ?? 'UNSIGNED-PAYLOAD';
  final canonicalRequest =
      getCanonicalRequest(request, signedHeaders, hashedPayload);
  final stringToSign = getStringToSign(canonicalRequest, requestDate, region);
  final signingKey = getSigningKey(requestDate, region, minio.secretKey);
  final credential = getCredential(minio.accessKey, region, requestDate);
  final signature = hex.encode(
    Hmac(sha256, signingKey).convert(stringToSign.codeUnits).bytes,
  );
  return '$signV4Algorithm Credential=$credential, SignedHeaders=${signedHeaders.join(';').toLowerCase()}, Signature=$signature';
}

// Ensure each step follows AWS Signature Version 4 specification.

List<String> getSignedHeaders(Iterable<String> headers) {
  const ignoredHeaders = {
    'authorization',
    'content-length',
    'content-type',
    'user-agent',
  };
  final result = headers
      .where((header) => !ignoredHeaders.contains(header.toLowerCase()))
      .map((header) => header.toLowerCase())
      .toList();
  result.sort();
  return result;
}

String getCanonicalRequest(
  MinioRequest request,
  List<String> signedHeaders,
  String hashedPayload,
) {
  final requestResource = encodePath(request.url.path);
  final headers = signedHeaders.map(
    (header) => '${header.toLowerCase()}:${request.headers[header]!.trim()}',
  );

  final queryKeys = request.url.queryParameters.keys.toList();
  queryKeys.sort();
  final requestQuery = queryKeys.map((key) {
    final value = request.url.queryParameters[key] ?? '';
    return '${encodeCanonicalQuery(key)}=${encodeCanonicalQuery(value)}';
  }).join('&');

  return [
    request.method.toUpperCase(),
    requestResource,
    requestQuery,
    '${headers.join('\n')}\n',
    signedHeaders.join(';').toLowerCase(),
    hashedPayload,
  ].join('\n');
}

String getStringToSign(
  String canonicalRequest,
  DateTime requestDate,
  String region,
) {
  final hash = sha256Hex(canonicalRequest);
  final scope = getScope(region, requestDate);
  return [
    signV4Algorithm,
    makeDateLong(requestDate),
    scope,
    hash,
  ].join('\n');
}

String getScope(String region, DateTime date) {
  return '${makeDateShort(date)}/$region/s3/aws4_request';
}

List<int> getSigningKey(DateTime date, String region, String secretKey) {
  final dateStamp = makeDateShort(date);
  final kSecret = utf8.encode('AWS4$secretKey');
  final kDate = Hmac(sha256, kSecret).convert(utf8.encode(dateStamp)).bytes;
  final kRegion = Hmac(sha256, kDate).convert(utf8.encode(region)).bytes;
  final kService = Hmac(sha256, kRegion).convert(utf8.encode('s3')).bytes;
  return Hmac(sha256, kService).convert(utf8.encode('aws4_request')).bytes;
}

String getCredential(String accessKey, String region, DateTime requestDate) {
  return '$accessKey/${getScope(region, requestDate)}';
}

String presignSignatureV4(
  Minio minio,
  MinioRequest request,
  String region,
  DateTime requestDate,
  int expires,
) {
  if (expires < 1) {
    throw MinioExpiresParamError('expires param cannot be less than 1 second');
  }
  if (expires > 604800) {
    throw MinioExpiresParamError('expires param cannot be greater than 7 days');
  }

  final iso8601Date = makeDateLong(requestDate);
  final signedHeaders = getSignedHeaders(request.headers.keys);
  final credential = getCredential(minio.accessKey, region, requestDate);

  final requestQuery = <String, String?>{};
  requestQuery['X-Amz-Algorithm'] = signV4Algorithm;
  requestQuery['X-Amz-Credential'] = credential;
  requestQuery['X-Amz-Date'] = iso8601Date;
  requestQuery['X-Amz-Expires'] = expires.toString();
  requestQuery['X-Amz-SignedHeaders'] = signedHeaders.join(';').toLowerCase();
  if (minio.sessionToken != null) {
    requestQuery['X-Amz-Security-Token'] = minio.sessionToken;
  }

  request = request.replace(
    url: request.url.replace(queryParameters: {
      ...request.url.queryParameters,
      ...requestQuery,
    }),
  );

  final canonicalRequest =
      getCanonicalRequest(request, signedHeaders, 'UNSIGNED-PAYLOAD');
  final stringToSign = getStringToSign(canonicalRequest, requestDate, region);
  final signingKey = getSigningKey(requestDate, region, minio.secretKey);
  final signature = sha256HmacHex(stringToSign, signingKey);
  return '${request.url}&X-Amz-Signature=$signature';
}

String postPresignSignatureV4(
  String region,
  DateTime date,
  String secretKey,
  String policyBase64,
) {
  final signingKey = getSigningKey(date, region, secretKey);
  return sha256HmacHex(policyBase64, signingKey);
}

String sha256HmacHex(String data, List<int> key) {
  final hmac = Hmac(sha256, key);
  return hex.encode(hmac.convert(utf8.encode(data)).bytes);
}

String encodeCanonicalQuery(String query) {
  // Encode the query following AWS rules
  return Uri.encodeQueryComponent(query).replaceAll('+', '%20');
}

String encodePath(String path) {
  // Encode the path following AWS rules
  return Uri.encodeFull(path);
}

String makeDateShort(DateTime date) {
  return date.toUtc().toIso8601String().split('T')[0].replaceAll('-', '');
}
