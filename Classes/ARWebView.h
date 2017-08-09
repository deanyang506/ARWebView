//
//  ARWebView.h
//  AipaiReconsitution
//
//  Created by Dean.Yang on 2017/7/14.
//  Copyright © 2017年 Dean.Yang. All rights reserved.
//

#import <UIKit/UIKit.h>

@class ARWebView;
@class ARWebViewUrlBridgeItem;

typedef NS_ENUM(NSInteger, ARWebViewNavigationType) {
    ARWebViewNavigationTypeLinkActivated,   // 跳转链接
    ARWebViewNavigationTypeFormSubmitted,   // 提交表单
    ARWebViewNavigationTypeBackForward,     // 后退或前进
    ARWebViewNavigationTypeReload,          // 重新加载
    ARWebViewNavigationTypeFormResubmitted, // 重新提交表单
    ARWebViewNavigationTypeOther = -1       // 其它
};

typedef BOOL(^ARWebViewUrlBridgeHandler)(ARWebView *webView,NSURL *targetUrl,ARWebViewNavigationType navigationType);

@protocol ARWebViewDelegate <NSObject>

@optional
- (void)webViewDidStartLoad:(ARWebView *)webView;
- (void)webViewLoad:(ARWebView *)webView progress:(double)progress;
- (void)webViewDidFinishLoad:(ARWebView *)webView;
- (void)webView:(ARWebView *)webView didFailLoadWithError:(NSError *)error;
- (BOOL)webView:(ARWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(ARWebViewNavigationType)navigationType;


@end

NS_CLASS_AVAILABLE_IOS(8_0) @interface ARWebView : UIView

- (instancetype)initWithDelegate:(id<ARWebViewDelegate>)delegate;

@property (nonatomic, weak) id<ARWebViewDelegate> delegate;
@property (nonatomic, readonly) NSString *title;
@property (nonatomic, readonly) NSURL *currentURL;
// 9.0以上可单独设置请求UA 9.0以下使用[[NSUserDefaults standardUserDefaults] registerDefaults:@{@"UserAgent":UserAgent}] 全局设置
@property (nonatomic, copy) NSString *customUserAgent NS_AVAILABLE_IOS(9_0);
@property (nonatomic, strong) NSString *cookie; // 可读取当前请求的cookie或者设置
@property (nonatomic, readonly) UIScrollView *scrollView;

/** http请求或者是本地html路径 */
- (void)loadWithUrl:(NSString *)urlString;
- (void)loadWithRequest:(NSURLRequest *)request;

@property (nonatomic, readonly, getter=isLoading) BOOL loading;
- (void)reload;
- (void)stopLoading;

@property (nonatomic, readonly) BOOL canGoBack;
@property (nonatomic, readonly) BOOL canGoForward;

/** 后退 */
- (void)goBack;
/** 前进 */
- (void)goForward;

/** 注册bridge
    @param urlScheme 协议名，如http
    @param host 匹配主机名，如果为nil则不匹配
    @result ARWebViewUrlBridgeItem 如果为nil则桥接错误，可用于remove参数
 */
- (ARWebViewUrlBridgeItem *)bridgeWithUrlScheme:(NSString *)urlScheme hostMatch:(NSString *)host handler:(ARWebViewUrlBridgeHandler)handler;

- (void)removeBridgeWithItem:(ARWebViewUrlBridgeItem *)item;

/** 执行JS */
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id obj, NSError *error))completionHandler;
/** 
    注册方法，以供JS调用
    observer 接收对象
    aSelector 方法选择器，方法名与调用的JS名相同，只带一个参数（id)
    注意：相同的方法即使不同的对象会被覆盖
 */
- (void)javaScriptObserver:(id)observer selector:(SEL)aSelector;

@end
