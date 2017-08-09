//
//  ARWebView.m
//  AipaiReconsitution
//
//  Created by Dean.Yang on 2017/7/14.
//  Copyright © 2017年 Dean.Yang. All rights reserved.
//

#import "ARWebView.h"
#import <WebKit/WebKit.h>

@interface ARWebViewUrlBridgeItem : NSObject
@property (nonatomic, strong) NSString *urlScheme;
@property (nonatomic, strong) NSString *hostMatch;
@property (nonatomic, copy) ARWebViewUrlBridgeHandler handler;
@end
@implementation ARWebViewUrlBridgeItem

@end

//WKNavigationDelegate  回调开始加载，收到内容，加载失败，加载拦截等
//WKUIDelegate 拦截新建的窗口，弹出的警告框，确认框，和输入框
//WKScriptMessageHandler 接收网页JS的调用
@interface ARWebView() <WKNavigationDelegate,WKUIDelegate,WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) double estimatedProgress;
@property (nonatomic, strong) NSMutableDictionary<NSString *,id> *jsDictionary;
@property (nonatomic, strong) NSMutableArray<ARWebViewUrlBridgeItem *> *bridgeItemArray;
@end

@implementation ARWebView

#pragma mark - view operation

- (void)willMoveToSuperview:(UIView *)newSuperview {
    [super willMoveToSuperview:newSuperview];
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.webView.frame = self.bounds;
}

#pragma mark - life cycle

- (void)dealloc {
    [self stopLoading];
    [self.webView removeObserver:self forKeyPath:@"estimatedProgress"];
    [self.webView.configuration.userContentController removeAllUserScripts];
}

- (instancetype)init {
    if (self = [super init]) {
        
        WKUserContentController *userContentController = [[WKUserContentController alloc] init];
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc]init];
        config.preferences.minimumFontSize = 10.0;
        config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        config.userContentController = userContentController;
        config.allowsInlineMediaPlayback = YES; // 允许内嵌视频播放
        
        self.webView = [[WKWebView alloc] initWithFrame:self.bounds configuration:config];
        self.webView.UIDelegate = self;
        self.webView.navigationDelegate = self;
        
        self.webView.backgroundColor = [UIColor clearColor];
        self.webView.opaque = NO;
        self.webView.multipleTouchEnabled = YES;
        self.webView.allowsBackForwardNavigationGestures = YES;
        self.webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        [self.webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:nil];
        
        [self addSubview:self.webView];
    }
    
    return self;
}

#pragma mark - public

- (instancetype)initWithDelegate:(id<ARWebViewDelegate>)delegate {
    if (self = [self init]) {
        self.delegate = delegate;
    }
    return self;
}

- (void)loadWithUrl:(NSString *)urlString {
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSCAssert(url, @"invalid url");
    
    NSString *scheme = [url scheme];
    if (scheme && ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
                   [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
        [self loadWithRequest:req];
    } else {
        NSURL *fileUrl = [NSURL fileURLWithPath:url.absoluteString];
        NSError *error = nil;
        NSString *htmlString = [[NSString alloc] initWithContentsOfURL:fileUrl encoding:NSUTF8StringEncoding error:&error];
        if (error) {
            NSLog(@"[ARWebView] read file html error");
        } else {
            [self.webView loadHTMLString:htmlString baseURL:fileUrl];
        }
        
    }
}

- (void)loadWithRequest:(NSURLRequest *)request {
    [self.webView loadRequest:request];
}

- (void)reload {
    [self.webView reload];
}

- (void)stopLoading {
    [self.webView stopLoading];
}

- (void)goBack {
    [self.webView goBack];
}

- (void)goForward {
    [self.webView goForward];
}

#pragma mark - Bridge

- (ARWebViewUrlBridgeItem *)bridgeWithUrlScheme:(NSString *)urlScheme hostMatch:(NSString *)host handler:(ARWebViewUrlBridgeHandler)handler {
    if (!urlScheme || !handler) {
        return nil;
    }
    
    ARWebViewUrlBridgeItem *item = [[ARWebViewUrlBridgeItem alloc] init];
    item.urlScheme = urlScheme;
    item.hostMatch = host;
    item.handler = handler;
    
    [self.bridgeItemArray addObject:item];
    return item;
}

- (void)removeBridgeWithItem:(ARWebViewUrlBridgeItem *)item {
    [self.bridgeItemArray removeObject:item];
}

#pragma mark - JS

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    [self.webView evaluateJavaScript:javaScriptString completionHandler:completionHandler];
}

- (void)javaScriptObserver:(id)observer selector:(SEL)aSelector {
    NSString *selectorString = NSStringFromSelector(aSelector);
    NSString *funName = [selectorString componentsSeparatedByString:@":"].firstObject;
    __weak typeof(observer) weakObserver = observer;
    [self.jsDictionary setObject:weakObserver forKey:funName];
    [self.webView.configuration.userContentController addScriptMessageHandler:self name:funName];
}
      
#pragma mark - getter & setter

- (NSString *)title {
    return self.webView.title;
}

- (NSURL *)currentURL {
    return self.webView.backForwardList.currentItem.URL;
}

- (NSString *)customUserAgent {
    return self.webView.customUserAgent;
}

- (void)setCustomUserAgent:(NSString *)customUserAgent {
    self.webView.customUserAgent = customUserAgent;
}

- (void)setCookie:(NSString *)cookie {
    WKUserScript * cookieScript = [[WKUserScript alloc] initWithSource:cookie injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [self.webView.configuration.userContentController addUserScript:cookieScript];
}

- (UIScrollView *)scrollView {
    return self.webView.scrollView;
}

- (BOOL)isLoading {
    return self.webView.isLoading;
}

- (BOOL)canGoBack {
    return self.webView.canGoBack;
}

- (BOOL)canGoForward {
    return self.webView.canGoForward;
}

- (NSMutableDictionary<NSString *,id> *)jsDictionary {
    if (!_jsDictionary) {
        _jsDictionary = [[NSMutableDictionary alloc] init];
    }
    return _jsDictionary;
}

- (NSMutableArray<ARWebViewUrlBridgeItem *> *)bridgeItemArray {
    if (!_bridgeItemArray) {
        _bridgeItemArray = [NSMutableArray array];
    }
    return _bridgeItemArray;
}

#pragma mark - Observer

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"estimatedProgress"]) {
        self.estimatedProgress = [change[NSKeyValueChangeNewKey] doubleValue];
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(webViewLoad:progress:)]) {
                [self.delegate webViewLoad:self progress:self.estimatedProgress];
            }
        });
    }
}

#pragma mark - WKNavigationDelegate

// 页面开始加载时调用
- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if ([self.delegate respondsToSelector:@selector(webViewDidStartLoad:)]) {
        [self.delegate webViewDidStartLoad:self];
    }
}

// 当内容开始返回时调用
- (void)webView:(WKWebView *)webView didCommitNavigation:(WKNavigation *)navigation {
    ;
}

// 页面加载完成之后调用
- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if ([self.delegate respondsToSelector:@selector(webViewDidFinishLoad:)]) {
        [self.delegate webViewDidFinishLoad:self];
    }
}

// 页面加载失败时调用
- (void)webView:(WKWebView *)webView didFailNavigation:(null_unspecified WKNavigation *)navigation withError:(nonnull NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webView:self didFailLoadWithError:error];
    }
}

-(void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    WKNavigationActionPolicy actionPolicy = WKNavigationActionPolicyAllow; // default
    
    NSURL *crtUrl = navigationAction.request.URL;
    for (ARWebViewUrlBridgeItem *bridgeItem in self.bridgeItemArray) {
        if ([bridgeItem.urlScheme isEqualToString:crtUrl.scheme]) {
            if (!bridgeItem.hostMatch || (bridgeItem.hostMatch && [bridgeItem.hostMatch isEqualToString:crtUrl.host])) {
                if (bridgeItem.handler) {
                    actionPolicy = bridgeItem.handler(self, crtUrl, (ARWebViewNavigationType)navigationAction.navigationType) ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel;
                    decisionHandler(actionPolicy);
                    return;
                }
            }
        }
    }
    
    if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        actionPolicy = [self.delegate webView:self shouldStartLoadWithRequest:navigationAction.request navigationType:(ARWebViewNavigationType)navigationAction.navigationType] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel;
    }
    
    if(actionPolicy == WKNavigationActionPolicyAllow) {
        if(navigationAction.targetFrame == nil) {
            [webView loadRequest:navigationAction.request];
        }
    }
    
    decisionHandler(actionPolicy);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandle {
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
    NSArray *cookies =[NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:response.URL];
    self.cookie = [cookies componentsJoinedByString:@";"];
    decisionHandle(WKNavigationResponsePolicyAllow);
}

/**
    iOS8系统下，自建证书的HTTPS链接，不调用此代理方法; 9.0以上正常，除非是认证证书
 */
- (void)webView:(WKWebView *)webView didReceiveAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition disposition, NSURLCredential *credential))completionHandler {
    if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
        if ([challenge previousFailureCount] == 0) {
            NSURLCredential *credential = [NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust];
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        } else {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        }
    } else {
        completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
    }
}

#pragma mark - WKUIDelegate

// 弹出警告框
- (void)webView:(WKWebView *)webView runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WKFrameInfo *)frame completionHandler:(void (^)(void))completionHandler {
    UIAlertAction *alertAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"确定",nil) style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        completionHandler();
    }];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:alertAction];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

// 弹出确认框
- (void)webView:(WKWebView *)webView runJavaScriptConfirmPanelWithMessage:(nonnull NSString *)message initiatedByFrame:(nonnull WKFrameInfo *)frame completionHandler:(nonnull void (^)(BOOL))completionHandler {
    UIAlertAction *alertActionCancel = [UIAlertAction actionWithTitle:NSLocalizedString(@"取消",nil)style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        completionHandler(NO);
    }];
    UIAlertAction *alertActionOK = [UIAlertAction actionWithTitle:NSLocalizedString(@"确定",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        completionHandler(YES);
    }];
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertController addAction:alertActionCancel];
    [alertController addAction:alertActionOK];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

// 弹出输入框
- (void)webView:(WKWebView *)webView runJavaScriptTextInputPanelWithPrompt:(nonnull NSString *)prompt defaultText:(nullable NSString *)defaultText initiatedByFrame:(nonnull WKFrameInfo *)frame completionHandler:(nonnull void (^)(NSString * _Nullable))completionHandler {
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:prompt message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = defaultText;
    }];
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"确定",nil) style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        UITextField *textField = alertController.textFields.firstObject;
        completionHandler(textField.text);
    }]];
    [[UIApplication sharedApplication].keyWindow.rootViewController presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - WKScriptMessageHandler

// message: 收到的脚本信息.
- (void)userContentController:(WKUserContentController *)userContentController didReceiveScriptMessage:(WKScriptMessage *)message {
    id observer = [self.jsDictionary objectForKey:message.name];
    if (observer) {
        SEL aSelector = NSSelectorFromString(message.name);
        if ([observer respondsToSelector:aSelector]) {
            IMP imp = [observer methodForSelector:aSelector];
            void (*func)(id, SEL) = (void *)imp;
            func(observer, aSelector);
        } else {
            aSelector = NSSelectorFromString([message.name stringByAppendingString:@":"]);
            if ([observer respondsToSelector:aSelector]) {
                IMP imp = [observer methodForSelector:aSelector];
                void (*func)(id, SEL, id) = (void *)imp;
                func(observer, aSelector, message.body);
            }
        }
    }
}

@end
