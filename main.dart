import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

void main() async {
  await dotenv.load(fileName: ".env");
  runApp(const FakeNewsApp());
}

class FakeNewsApp extends StatelessWidget {
  const FakeNewsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Fake ou Não?',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.deepPurple,
          secondary: Colors.deepPurple[200]!,
        ),
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.deepPurple[400],
          elevation: 0,
        ),
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class NewsService {
  static final Dio _dio = Dio();
  static final String _newsApiKey = dotenv.env['NEWS_API_KEY']!;
  static const String _newsApiUrl = 'https://newsapi.org/v2/';

  static Future<List<Map<String, dynamic>>> fetchTopNews({
    String category = 'general',
    String country = 'br',
  }) async {
    try {
      final response = await _dio.get(
        '${_newsApiUrl}top-headlines',
        queryParameters: {
          'country': country,
          'category': category,
          'apiKey': _newsApiKey,
          'pageSize': 20,
        },
      );

      return (response.data['articles'] as List).map((article) {
        return {
          'title': article['title'] ?? 'Sem título',
          'source': article['source']['name'] ?? 'Fonte desconhecida',
          'time': _formatDate(article['publishedAt']),
          'content': article['description'] ?? 'Clique para ver detalhes',
          'image': article['urlToImage'] ?? 'assets/images/placeholder.jpg',
          'url': article['url'] ?? '',
          'verified': null,
          'icon': _getCategoryIcon(category),
          'tag': _mapCategoryToTag(category),
        };
      }).toList();
    } catch (e) {
      throw Exception('Erro ao carregar notícias: $e');
    }
  }

  static String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return DateFormat('HH:mm - dd/MM/yyyy').format(date);
    } catch (e) {
      return 'Horário desconhecido';
    }
  }

  static IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'business':
        return Icons.attach_money;
      case 'entertainment':
        return Icons.movie;
      case 'health':
        return Icons.medical_services;
      case 'science':
        return Icons.science;
      case 'sports':
        return Icons.sports_soccer;
      case 'technology':
        return Icons.smartphone;
      default:
        return Icons.article;
    }
  }

  static String _mapCategoryToTag(String category) {
    return category == 'general'
        ? 'Geral'
        : category[0].toUpperCase() + category.substring(1);
  }
}

class FactCheckApi {
  static final String _factCheckApiKey =
      dotenv.env['GOOGLE_FACT_CHECK_API_KEY'] ?? '';
  static const String _factCheckUrl =
      'https://factchecktools.googleapis.com/v1alpha1/';

  static Future<List<dynamic>> searchClaims(String query) async {
    try {
      final response = await http.get(
        Uri.parse(
          '${_factCheckUrl}claims:search?query=${Uri.encodeQueryComponent(query)}&key=$_factCheckApiKey&languageCode=pt',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['claims'] ?? [];
      } else {
        throw Exception(
          'Falha ao carregar verificações: ${response.statusCode}',
        );
      }
    } catch (e) {
      throw Exception('Erro na conexão: $e');
    }
  }

  static Future<Map<String, dynamic>?> verifyClaim(String claimText) async {
    try {
      final claims = await searchClaims(claimText);
      if (claims.isNotEmpty) {
        final verification = claims.first;
        return {
          'rating': verification['claimReview'][0]['textualRating'],
          'publisher': verification['claimReview'][0]['publisher']['name'],
          'reviewDate': verification['claimReview'][0]['reviewDate'],
          'url': verification['claimReview'][0]['url'],
          'confidence': 0.9,
        };
      }
      return null;
    } catch (e) {
      debugPrint('Erro na verificação: $e');
      return null;
    }
  }
}

class NewsVerificationService {
  static final Map<String, bool> _fakeNewsDatabase = {
    "vacina covid contém microchip": true,
    "terra é plana": true,
    "eleições 2022 foram fraudadas": false,
  };

  static final List<String> _trustedSources = [
    "g1",
    "bbc",
    "reuters",
    "ap",
    "agência lupa",
    "aos fatos",
  ];

  static Future<Map<String, dynamic>> verifyNews(
    Map<String, dynamic> news,
  ) async {
    final lowerTitle = news['title'].toString().toLowerCase();

    // 1. Verificação local
    if (_fakeNewsDatabase.containsKey(lowerTitle)) {
      return {
        'status': _fakeNewsDatabase[lowerTitle]! ? 'fake' : 'true',
        'confidence': 0.95,
        'method': 'database_match',
      };
    }

    // 2. Verificação por API
    try {
      final apiResult = await FactCheckApi.verifyClaim(news['title']);
      if (apiResult != null) {
        return {
          'status': _interpretGoogleRating(apiResult['rating']),
          'confidence': apiResult['confidence'],
          'method': 'google_fact_check',
          'details': apiResult,
        };
      }
    } catch (e) {
      debugPrint('Erro na API: $e');
    }

    // 3. Análise local
    final sourceScore = _checkSourceTrustworthiness(news['source']);
    final contentAnalysis = _analyzeContent(news['content'] ?? news['title']);

    return _calculateResult(sourceScore, contentAnalysis);
  }

  static String _interpretGoogleRating(String rating) {
    final lowerRating = rating.toLowerCase();
    if (lowerRating.contains('falsa') || lowerRating.contains('false'))
      return 'fake';
    if (lowerRating.contains('verdadeira') || lowerRating.contains('true'))
      return 'true';
    return 'unverified';
  }

  static double _checkSourceTrustworthiness(String source) {
    final lowerSource = source.toLowerCase();
    return _trustedSources.any((s) => lowerSource.contains(s)) ? 0.9 : 0.5;
  }

  static Map<String, dynamic> _analyzeContent(String content) {
    final lowerContent = content.toLowerCase();
    int redFlags = 0;

    const suspiciousPhrases = [
      "urgente",
      "compartilhe rápido",
      "viralizou",
      "especialistas surpresos",
      "ninguém está falando sobre isso",
    ];

    redFlags += suspiciousPhrases.where((p) => lowerContent.contains(p)).length;
    redFlags += "!".allMatches(content).length > 3 ? 1 : 0;

    return {
      'redFlags': redFlags,
      'score': 1.0 - (redFlags * 0.1).clamp(0.0, 1.0),
    };
  }

  static Map<String, dynamic> _calculateResult(
    double sourceScore,
    Map<String, dynamic> contentAnalysis,
  ) {
    final combinedScore =
        (sourceScore * 0.7) + (contentAnalysis['score'] * 0.3);

    if (combinedScore > 0.8)
      return {
        'status': 'true',
        'confidence': combinedScore,
        'method': 'local_analysis',
      };
    if (combinedScore < 0.4)
      return {
        'status': 'fake',
        'confidence': 1.0 - combinedScore,
        'method': 'local_analysis',
      };
    return {
      'status': 'unverified',
      'confidence': 0.5,
      'method': 'local_analysis',
    };
  }
}

class NewsDetailPage extends StatelessWidget {
  final Map<String, dynamic> news;

  const NewsDetailPage({super.key, required this.news});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(news['source'])),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              news['title'],
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Publicado em: ${news['time']}',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 24),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.deepPurple[100],
                borderRadius: BorderRadius.circular(12),
                image: DecorationImage(
                  image:
                      news['image'].startsWith('http')
                          ? NetworkImage(news['image']) as ImageProvider
                          : AssetImage(news['image']),
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              news['content'],
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 30),
            if (news['verified'] != null && news['verificationDetails'] != null)
              _buildVerificationResult(news),
            if (news['url'] != null && news['url'].isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: ElevatedButton(
                  onPressed: () => launchUrl(Uri.parse(news['url'])),
                  child: const Text('Ver notícia completa'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificationResult(Map<String, dynamic> news) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: news['verified'] == false ? Colors.green[50] : Colors.red[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: news['verified'] == false ? Colors.green : Colors.red,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                news['verified'] == false ? Icons.verified : Icons.warning,
                color: news['verified'] == false ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 8),
              Text(
                news['verified'] == false
                    ? 'Notícia verificada como VERDADEIRA'
                    : 'ATENÇÃO: Notícia verificada como FALSA',
                style: TextStyle(
                  color: news['verified'] == false ? Colors.green : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (news['verificationDetails']['method'] == 'google_fact_check')
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fonte: ${news['verificationDetails']['details']['publisher']}',
                  ),
                  Text(
                    'Data: ${news['verificationDetails']['details']['reviewDate']}',
                  ),
                  InkWell(
                    onTap:
                        () => launchUrl(
                          Uri.parse(
                            news['verificationDetails']['details']['url'],
                          ),
                        ),
                    child: Text(
                      'Ver relatório completo',
                      style: TextStyle(
                        color: Colors.blue[600],
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Confiança: ${(news['verificationDetails']['confidence'] * 100).toStringAsFixed(0)}%',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color:
                    news['verified'] == false
                        ? Colors.green[800]
                        : Colors.red[800],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedCategory = 0;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _allNews = [];

  final List<String> _categories = [
    'Geral',
    'Negócios',
    'Entretenimento',
    'Saúde',
    'Ciência',
    'Esportes',
    'Tecnologia',
  ];

  @override
  void initState() {
    super.initState();
    _loadNews();
  }

  Future<void> _loadNews() async {
    setState(() => _isLoading = true);
    try {
      final news = await NewsService.fetchTopNews(
        category: _getApiCategory(_selectedCategory),
      );
      setState(() => _allNews = news);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar notícias: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _getApiCategory(int index) {
    switch (index) {
      case 0:
        return 'general';
      case 1:
        return 'business';
      case 2:
        return 'entertainment';
      case 3:
        return 'health';
      case 4:
        return 'science';
      case 5:
        return 'sports';
      case 6:
        return 'technology';
      default:
        return 'general';
    }
  }

  List<Map<String, dynamic>> get _filteredNews {
    if (_selectedCategory == 0) return _allNews;
    return _allNews
        .where((news) => news['tag'] == _categories[_selectedCategory])
        .toList();
  }

  void _verifyNews(int index) async {
    final newsIndex = _allNews.indexOf(_filteredNews[index]);

    setState(() {
      _allNews[newsIndex]['verified'] = 'analisando';
      _allNews[newsIndex]['verificationDetails'] = null;
    });

    try {
      final result = await NewsVerificationService.verifyNews(
        _filteredNews[index],
      );
      setState(() {
        _allNews[newsIndex]['verificationDetails'] = result;
        _allNews[newsIndex]['verified'] =
            result['status'] == 'true'
                ? false
                : result['status'] == 'fake'
                ? true
                : null;
      });
    } catch (e) {
      setState(() => _allNews[newsIndex]['verified'] = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro na verificação: ${e.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Alethea'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadNews),
        ],
      ),
      body:
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                children: [
                  _buildSearchBar(),
                  _buildCategorySelector(),
                  Expanded(child: _buildNewsList()),
                ],
              ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Pesquisar notícias...',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        onSubmitted: (value) => _searchNews(value),
      ),
    );
  }

  Widget _buildCategorySelector() {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: ChoiceChip(
              label: Text(_categories[index]),
              selected: _selectedCategory == index,
              onSelected: (selected) {
                setState(() => _selectedCategory = index);
                _loadNews();
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNewsList() {
    return ListView.builder(
      itemCount: _filteredNews.length,
      itemBuilder: (context, index) {
        final news = _filteredNews[index];
        return Card(
          margin: const EdgeInsets.all(8),
          child: InkWell(
            onTap:
                () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NewsDetailPage(news: news),
                  ),
                ),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNewsImage(news),
                  _buildNewsContent(news, index),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildNewsImage(Map<String, dynamic> news) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        news['image'],
        height: 180,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder:
            (_, __, ___) => Container(
              height: 180,
              color: Colors.grey[200],
              child: const Center(child: Icon(Icons.image_not_supported)),
            ),
      ),
    );
  }

  Widget _buildNewsContent(Map<String, dynamic> news, int index) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(news['icon'] ?? Icons.article, size: 20),
              const SizedBox(width: 8),
              Text(
                news['source'],
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text(news['time'].split(' - ')[0]),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            news['title'],
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Chip(label: Text(news['tag'])),
              const Spacer(),
              _buildVerificationButton(news, index),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationButton(Map<String, dynamic> news, int index) {
    if (news['verified'] == 'analisando') {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final isVerified = news['verified'] != null;
    final isTrue = news['verified'] == false;

    return OutlinedButton.icon(
      onPressed: isVerified ? null : () => _verifyNews(index),
      icon: Icon(
        isVerified
            ? (isTrue ? Icons.verified : Icons.warning)
            : Icons.fact_check,
        color:
            isVerified
                ? (isTrue ? Colors.green : Colors.red)
                : Colors.deepPurple,
      ),
      label: Text(
        isVerified ? (isTrue ? 'Verificada' : 'Possível Fake') : 'Verificar',
        style: TextStyle(
          color:
              isVerified
                  ? (isTrue ? Colors.green : Colors.red)
                  : Colors.deepPurple,
        ),
      ),
    );
  }

  void _searchNews(String query) {
    // Implementação simplificada - pode ser melhorada
    setState(() {
      _allNews =
          _allNews
              .where(
                (news) =>
                    news['title'].toLowerCase().contains(query.toLowerCase()),
              )
              .toList();
    });
  }
}
