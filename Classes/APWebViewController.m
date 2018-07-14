//
//  APWebViewController.m
//  Aipai
//
//  Created by YangWeiChang on 2018/6/24.
//  Copyright © 2018年 www.aipai.com. All rights reserved.
//

#import "APWebViewController.h"
#import <objc/runtime.h>
#import <WebKit/WebKit.h>

static NSMutableDictionary<NSString *, NSValue *> *_webBridgeItemDictionary;
static NSMutableDictionary<NSString *, NSValue *> *_webJavaScriptDictionary;

#pragma mark - inputAccessoryView

@interface UIView(APWbInputAccessoryView)
@property (nonatomic, strong) UIView *wbInputAccessoryView;
@end
@implementation UIView(APWbInputAccessoryView)

- (void)setWbInputAccessoryView:(UIView *)wbInputAccessoryView {
    objc_setAssociatedObject(self, @selector(wbInputAccessoryView), wbInputAccessoryView, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (UIView *)wbInputAccessoryView {
    return (UIView *)objc_getAssociatedObject(self, @selector(wbInputAccessoryView));
}

@end

@interface APWbInputAccessoryView : UIView
@end
@implementation APWbInputAccessoryView

- (UIView *)inputAccessoryView {
    return self.wbInputAccessoryView;
}

@end

#pragma mark - WebView

//WKNavigationDelegate  回调开始加载，收到内容，加载失败，加载拦截等
//WKUIDelegate 拦截新建的窗口，弹出的警告框，确认框，和输入框
//WKScriptMessageHandler 接收网页JS的调用
@interface APWebViewController() <WKNavigationDelegate,WKUIDelegate,WKScriptMessageHandler>
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, assign) double estimatedProgress;
@property (nonatomic, strong) NSURLRequest *currentUrlRequest;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) NSMutableSet *jsFunSet;
@end

@implementation APWebViewController

+ (void)initialize {
    //添加mobile_guide的Cookie
    NSMutableDictionary *cookieProperties = [NSMutableDictionary dictionary];
    [cookieProperties setObject:@"1" forKey:NSHTTPCookieValue];
    [cookieProperties setObject:@"mobile_guide" forKey:NSHTTPCookieName];
    [cookieProperties setObject:@"/" forKey:NSHTTPCookiePath];
    [cookieProperties setObject:kAPDomain forKey:NSHTTPCookieDomain];
    [cookieProperties setObject:[NSDate dateWithTimeIntervalSinceNow:10000000] forKey:NSHTTPCookieExpires];
    NSHTTPCookie *newCookie = [NSHTTPCookie cookieWithProperties:cookieProperties];
    [[NSHTTPCookieStorage sharedHTTPCookieStorage] setCookie:newCookie];
}

/// !!!: 注册桥接协议
+ (void)registerBrideg:(NSString *)scheme delegate:(id<APWebBridgeModuleProtocol>)delegate {
    if (scheme.length == 0) {
        return;
    }
    @synchronized(self) {
        if (_webBridgeItemDictionary == nil) {
            _webBridgeItemDictionary = [NSMutableDictionary dictionary];
        }
        
        NSValue *value = [NSValue valueWithNonretainedObject:delegate];
        _webBridgeItemDictionary[scheme] = value;
    }
}

/// !!!: 注入脚本方法
+ (void)registerJavaScriptWithFun:(NSString *)fun delegate:(id<APWebJavaScriptModuleProtocol>)delegate {
    if (fun.length == 0) {
        return;
    }
    @synchronized(self) {
        if (_webJavaScriptDictionary == nil) {
            _webJavaScriptDictionary = [NSMutableDictionary dictionary];
        }
        
        NSValue *value = [NSValue valueWithNonretainedObject:delegate];
        _webJavaScriptDictionary[fun] = value;
    }
}

- (void)dealloc {
    [_webView stopLoading];
    [_webView.configuration.userContentController removeAllUserScripts];
    
    @try {
        [_webView removeObserver:self forKeyPath:@"estimatedProgress"];
        [_webView removeObserver:self forKeyPath:@"title"];
    } @catch(NSException *e) { }
}

- (instancetype)init {
    if (self = [super init]) {
        _showProgress = YES;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.navigationController.navigationBar.tintColor  = [UIColor colorWithRGB:0x333333];
    [self.view addSubview:self.webView];
    [self.view addSubview:self.progressView];
    self.progressView.hidden = !self.showProgress;
    self.webView.scrollView.backgroundColor = [UIColor colorWithRGB:0xF5F5F5];
    self.webView.scrollView.decelerationRate = 0.998f;
    
    [self.view setNeedsUpdateConstraints];
    
    [self loadWithRequest:self.currentUrlRequest];
}

- (void)updateViewConstraints {
    [super updateViewConstraints];
    
    [self.webView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.top.right.equalTo(@0);
        if (@available(iOS 11.0, *)) {
            make.bottom.equalTo(self.view.mas_safeAreaLayoutGuideBottom);
        } else {
            make.bottom.equalTo(@0);
        }
    }];
    
    [self.progressView mas_remakeConstraints:^(MASConstraintMaker *make) {
        make.left.equalTo(@0);
        make.top.equalTo(@1);
        make.right.equalTo(@0);
        make.height.equalTo(@2);
    }];
}

- (void)closeBarItemClicked:(UIBarButtonItem *)barButtonItem {
    if (self.canCloseCallback && !self.canCloseCallback()) {
        return;
    }
    [self closeOrBack];;
}

- (void)closeOrBack {
    if (self.webView.canGoBack) {
        [self.webView goBack];
    } else {
        if (self.navigationController.childViewControllers.firstObject == self) {
            [self.navigationController dismissViewControllerAnimated:YES completion:nil];
        } else {
            [self.navigationController popViewControllerAnimated:YES];
        }
    }
}

- (void)headerRefresh:(id)sender {
    [self.webView reload];
    [self.webView.scrollView.mj_header endRefreshing];
}

#pragma mark - public

- (void)loadWithUrl:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        return;
    }
    
    NSString *scheme = [url scheme];
    if (scheme && ([scheme caseInsensitiveCompare:@"http"] == NSOrderedSame ||
                   [scheme caseInsensitiveCompare:@"https"] == NSOrderedSame)) {
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestUseProtocolCachePolicy timeoutInterval:10];
        [self loadWithRequest:[req copy]];
    } else {
        NSURL *fileUrl = [NSURL fileURLWithPath:url.absoluteString];
        NSError *error = nil;
        NSString *htmlString = [[NSString alloc] initWithContentsOfURL:fileUrl encoding:NSUTF8StringEncoding error:&error];
        if (!error) {
            [self.webView loadHTMLString:htmlString baseURL:fileUrl];
        }
    }
}

- (void)loadWithRequest:(NSURLRequest *)request {
    self.currentUrlRequest = request;
    if (self.isViewLoaded) {
        [self.webView loadRequest:request];
    }
}

- (void)setCookie:(NSString *)cookie {
    WKUserScript * cookieScript = [[WKUserScript alloc] initWithSource:cookie injectionTime:WKUserScriptInjectionTimeAtDocumentStart forMainFrameOnly:NO];
    [self.webView.configuration.userContentController addUserScript:cookieScript];
}

- (UIScrollView *)scrollView {
    return self.webView.scrollView;
}

- (void)setInputAccessoryView:(UIView *)accessoryView {
    
    WKWebView *webView = self.webView;
    UIView *targetView;
    
    for (UIView *view in webView.scrollView.subviews) {
        if([[view.class description] hasPrefix:@"WKContent"]) {
            targetView = view;
            break;
        }
    }
    
    if (!targetView) {
        return;
    }
    
    targetView.wbInputAccessoryView = accessoryView;
    NSString *inputAccessoryViewClassName = [NSString stringWithFormat:@"%@_InputAccessoryView", targetView.class.superclass];
    Class newClass = NSClassFromString(inputAccessoryViewClassName);
    
    if(newClass == nil) {
        newClass = objc_allocateClassPair(targetView.class, [inputAccessoryViewClassName cStringUsingEncoding:NSASCIIStringEncoding], 0);
        if(!newClass) {
            return;
        }
        
        Class inputAccessoryClass = [APWbInputAccessoryView class];
        
        Method method = class_getInstanceMethod(inputAccessoryClass, @selector(inputAccessoryView));
        
        class_addMethod(newClass, @selector(inputAccessoryView), method_getImplementation(method), method_getTypeEncoding(method));
        
        objc_registerClassPair(newClass);
    }
    
    object_setClass(targetView, newClass);
}

- (void)registerJavaScriptWithFun:(NSString *)fun {
    if (fun.length == 0) {
        return;
    }
    
    if ([self.jsFunSet containsObject:fun]) {
        return;
    }
    
    [self.jsFunSet addObject:fun];
    WKUserContentController *userContentController = self.webView.configuration.userContentController;
    [userContentController removeScriptMessageHandlerForName:fun];
    [userContentController addScriptMessageHandler:self name:fun];
    NSString *javaScriptSource = [NSString stringWithFormat:@"window.newaipai.%@ = function(data) { window.webkit.messageHandlers.%@.postMessage(data); }",fun,fun];
    WKUserScript *userScript = [[WKUserScript alloc] initWithSource:javaScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
    [userContentController addUserScript:userScript];
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
    if ([object isEqual:self.webView]) {
        if ([keyPath isEqualToString:@"title"]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                self.title = self.webView.title;
            });
        }
    }
}

#pragma mark - JS

- (void)callbackWithEvent:(NSString *)event param:(id)param cbparam:(id)cbparam completionHandler:(void (^)(id, NSError *))completionHandler {
    
    if (event.length == 0) {
        return;
    }
    
    if (!param) {
        param = @{};
    }
    
    if (!cbparam) {
        cbparam = @{};
    }
    
    NSString *paramJson;
    if ([NSJSONSerialization isValidJSONObject:param]) {
        paramJson = [param yy_modelToJSONString];
    } else {
        paramJson = [NSString stringWithFormat:@"'%@'",param];
    }
    
    NSString *cbparamJson;
    if ([NSJSONSerialization isValidJSONObject:cbparam]) {
        cbparamJson = [cbparam yy_modelToJSONString];
    } else {
        cbparamJson = [NSString stringWithFormat:@"'%@'",cbparam];
    }
    
    NSString *js = [NSString stringWithFormat:@"(function(){var evt = new window.Event('%@'); evt.param = %@; evt.cbparam= %@; window.document.dispatchEvent(evt);})();",event, paramJson ,cbparamJson];
    [self evaluateJavaScript:js completionHandler:completionHandler];
}

- (void)callbakJSWithFun:(NSString *)fun params:(NSArray *)params completionHandler:(void (^)(id, NSError *))completionHandler {
    NSMutableArray *paramArray = [NSMutableArray array];
    [params enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSString *paramJson;
        if ([NSJSONSerialization isValidJSONObject:obj]) {
            paramJson = [obj yy_modelToJSONString];
        } else {
            paramJson = [NSString stringWithFormat:@"'%@'",obj];
        }
        [paramArray addObject:paramJson];
    }];
    
    NSString *paramString = @"";
    if (paramArray.count) {
        paramString = [paramArray componentsJoinedByString:@","];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [self evaluateJavaScript:[NSString stringWithFormat:@"%@(%@)",fun,paramString] completionHandler:completionHandler];
    });
}

- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id, NSError *))completionHandler {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.webView evaluateJavaScript:javaScriptString completionHandler:completionHandler];
    });
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
        [self.delegate webViewController:self didFailLoadWithError:error];
    }
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(webView:didFailLoadWithError:)]) {
        [self.delegate webViewController:self didFailLoadWithError:error];
    }
}

-(void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)navigationAction decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    
    NSURL *crtUrl = navigationAction.request.URL;
    if (navigationAction.navigationType == WKNavigationTypeLinkActivated) {
        dispatch_async(dispatch_get_main_queue(), ^{
            APWebViewController *webVC = [[APWebViewController alloc] init];
            [webVC loadWithUrl:navigationAction.request.URL.absoluteString];
            [self.navigationController pushViewController:webVC animated:YES];
        });
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    
    WKNavigationActionPolicy actionPolicy = WKNavigationActionPolicyAllow; // default
    id<APWebBridgeModuleProtocol> bridgeDelegate = [_webBridgeItemDictionary objectForKey:crtUrl.scheme].nonretainedObjectValue;
    actionPolicy = bridgeDelegate ? WKNavigationActionPolicyCancel : WKNavigationActionPolicyAllow;
    
    if (bridgeDelegate && [bridgeDelegate conformsToProtocol:@protocol(APWebBridgeModuleProtocol)]) {
        NSString *host = [crtUrl host];
        id data = nil;
        NSArray *params = [crtUrl.absoluteString componentsSeparatedByString:@"/"];
        if (params.count > 3) {
            NSString *parmeString = [params[3] stringByURLDecode];
            if (parmeString) {
                data = [NSJSONSerialization JSONObjectWithData:[parmeString dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
                if (!data) {
                    if (![parmeString isEqualToString:@"null"]) {
                        data = parmeString;
                    }
                }
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([bridgeDelegate respondsToSelector:@selector(webBridgeWithScheme:bridge:data:navigationType:webViewController:)]) {
                [bridgeDelegate webBridgeWithScheme:crtUrl.scheme bridge:host data:data navigationType:(APWebViewNavigationType)navigationAction.navigationType webViewController:self];
            }
        });
    }
    
    if ([self.delegate respondsToSelector:@selector(webView:shouldStartLoadWithRequest:navigationType:)]) {
        actionPolicy = [self.delegate webViewController:self shouldStartLoadWithRequest:navigationAction.request navigationType:(APWebViewNavigationType)navigationAction.navigationType] ? WKNavigationActionPolicyAllow : WKNavigationActionPolicyCancel;
    }
    
    if(actionPolicy == WKNavigationActionPolicyAllow) {
        if(navigationAction.targetFrame == nil) {
            [webView loadRequest:navigationAction.request];
        }
        self.canCloseCallback = nil;
    }
    
    decisionHandler(actionPolicy);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)navigationResponse decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandle {
    if ([navigationResponse.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)navigationResponse.response;
        NSArray *cookies =[NSHTTPCookie cookiesWithResponseHeaderFields:[response allHeaderFields] forURL:response.URL];
        self.cookie = [cookies componentsJoinedByString:@";"];
    }
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
        if(completionHandler)
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
    id<APWebJavaScriptModuleProtocol> delegate = [_webJavaScriptDictionary objectForKey:message.name].nonretainedObjectValue;
    if (delegate && [delegate conformsToProtocol:@protocol(APWebJavaScriptModuleProtocol)]) {
        if ([delegate respondsToSelector:@selector(webJavaScriptWithFun:data:webViewController:)]) {
            [delegate webJavaScriptWithFun:message.name data:message.body webViewController:self];
        }
    }
    if ([self.delegate respondsToSelector:@selector(webJavaScriptWithFun:data:webViewController:)]) {
        [self.delegate webJavaScriptWithFun:message.name data:message.body webViewController:self];
    }
}

#pragma mark - setter

- (void)setShowProgress:(BOOL)showProgress {
    _showProgress = showProgress;
    _progressView.hidden = !_showProgress;
}

- (void)setEstimatedProgress:(double)estimatedProgress {
    if (_showProgress) {
        _estimatedProgress = MIN(MAX(0, estimatedProgress), 1.0);
        if (_estimatedProgress == 1) {
            self.progressView.progress = 1;
            CGFloat delayTime = 1.2;
            if([self.webView.URL.absoluteString hasPrefix:@"file://"]) {
                delayTime = 1.5;
            }
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayTime * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.progressView.hidden = YES;
                self.progressView.progress = 0;
            });
        } else if (_estimatedProgress == 0) {
            self.progressView.progress = 0;
            self.progressView.hidden = YES;
        } else {
            self.progressView.hidden = NO;
            self.progressView.progress = _estimatedProgress;
        }
    }
}

#pragma mark - getter

- (WKWebView *)webView {
    if (!_webView) {
        WKUserContentController *userContentController = [[WKUserContentController alloc] init];
        NSString *javaScriptSource = @"window.newaipai = {};";
            WKUserScript *userScript = [[WKUserScript alloc] initWithSource:javaScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
        [userContentController addUserScript:userScript];
        __weak typeof(self) _weakSelf = self;
        [_webJavaScriptDictionary.allKeys enumerateObjectsUsingBlock:^(NSString * _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            [userContentController addScriptMessageHandler:_weakSelf name:obj];
            NSString *javaScriptSource = [NSString stringWithFormat:@"window.newaipai.%@ = function(data) { window.webkit.messageHandlers.%@.postMessage(data); }",obj,obj];
            WKUserScript *userScript = [[WKUserScript alloc] initWithSource:javaScriptSource injectionTime:WKUserScriptInjectionTimeAtDocumentEnd forMainFrameOnly:NO];
            [userContentController addUserScript:userScript];
        }];
        
        WKWebViewConfiguration *config = [[WKWebViewConfiguration alloc]init];
        config.preferences.minimumFontSize = 10.0;
        config.preferences.javaScriptCanOpenWindowsAutomatically = NO;
        config.userContentController = userContentController;
        config.allowsInlineMediaPlayback = YES; // 允许内嵌视频播放
        
        _webView = [[WKWebView alloc] initWithFrame:CGRectZero configuration:config];
        _webView.UIDelegate = self;
        _webView.navigationDelegate = self;
        
        _webView.backgroundColor = [UIColor clearColor];
        _webView.opaque = NO;
        _webView.multipleTouchEnabled = YES;
        _webView.allowsBackForwardNavigationGestures = YES;
        _webView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        
        [_webView addObserver:self forKeyPath:@"estimatedProgress" options:NSKeyValueObservingOptionNew context:NULL];
        [_webView addObserver:self forKeyPath:@"title" options:(NSKeyValueObservingOptionOld | NSKeyValueObservingOptionNew) context:NULL];
    }
    return _webView;
}

- (UIProgressView *)progressView {
    if (_progressView == nil) {
        _progressView = [[UIProgressView alloc] initWithFrame:CGRectZero];
        _progressView.transform = CGAffineTransformMakeScale(1, 1);
        _progressView.tintColor = [UIColor colorWithHexString:cAPColor];
        _progressView.trackTintColor = [UIColor clearColor];
    }
    return _progressView;
}

- (NSMutableSet *)jsFunSet {
    if (!_jsFunSet) {
        _jsFunSet = [NSMutableSet set];
    }
    return _jsFunSet;
}

@end
