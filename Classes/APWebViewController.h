//
//  APWebViewController.h
//  Aipai
//
//  Created by YangWeiChang on 2018/6/24.
//  Copyright © 2018年 www.aipai.com. All rights reserved.
//

#import "APBaseViewController.h"

@class APWebViewUrlBridgeItem;
@class APWebViewController;

typedef NS_ENUM(NSInteger, APWebViewNavigationType) {
    APWebViewNavigationTypeLinkActivated,   // 跳转链接
    APWebViewNavigationTypeFormSubmitted,   // 提交表单
    APWebViewNavigationTypeBackForward,     // 后退或前进
    APWebViewNavigationTypeReload,          // 重新加载
    APWebViewNavigationTypeFormResubmitted, // 重新提交表单
    APWebViewNavigationTypeOther = -1       // 其它
};

@protocol APWebBridgeModuleProtocol <NSObject>

/**
 协议桥接

 @param scheme 协议名
 @param bridge host
 @param data 数据
 @param navigationType 链接加载方式
 @param webViewController web页面对象
 */
- (void)webBridgeWithScheme:(NSString *)scheme bridge:(NSString *)bridge data:(id)data navigationType:(APWebViewNavigationType)navigationType webViewController:(APWebViewController *)webViewController;
@end

@protocol APWebJavaScriptModuleProtocol <NSObject>

/**
 脚本方法

 @param fun 方法名
 @param data 数据对象
 @param webViewController web页面对象
 */
- (void)webJavaScriptWithFun:(NSString *)fun data:(id)data webViewController:(APWebViewController *)webViewController;
@end

@protocol APWebViewControllerDelegate <APWebJavaScriptModuleProtocol>
@optional
- (void)webViewDidStartLoad:(APWebViewController *)webViewController;
- (void)webViewLoad:(APWebViewController *)webViewController progress:(double)progress;
- (void)webViewDidFinishLoad:(APWebViewController *)webViewController;
- (void)webViewController:(APWebViewController *)webViewController didFailLoadWithError:(NSError *)error;
- (BOOL)webViewController:(APWebViewController *)webViewController shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(APWebViewNavigationType)navigationType;
@end

@interface APWebViewController : APBaseViewController

/**
 注册桥接协议
 相同的协议名会被覆盖代理对象
 */
+ (void)registerBrideg:(NSString *)scheme delegate:(id<APWebBridgeModuleProtocol>)delegate;

/**
 注册JS方法,
 相同的方法名会被覆盖代理对象
 */
+ (void)registerJavaScriptWithFun:(NSString *)fun delegate:(id<APWebJavaScriptModuleProtocol>)delegate;

/**
 实例方式注入脚本
 */
- (void)registerJavaScriptWithFun:(NSString *)fun;

#pragma mark - instance

@property (nonatomic, copy) BOOL(^canCloseCallback)(void); ///能否关闭回调，返回YES关闭
@property (nonatomic, weak) id<APWebViewControllerDelegate> delegate;
@property (nonatomic, readonly) NSString *documentTitle;            ///<网页标题
@property (nonatomic, strong) NSString *cookie;                     ///<可读取当前请求的cookie或者设置
@property (nonatomic, readonly) UIScrollView *scrollView;           ///<页面滑动器
@property (nonatomic, assign) BOOL showProgress;                    ///显示加载进度，默认为YES；

/** http请求或者是本地html路径 */
- (void)loadWithUrl:(NSString *)urlString;
- (void)loadWithRequest:(NSURLRequest *)request;
- (void)closeOrBack;
///键盘的附带视图为nil的时候将不显示
- (void)setInputAccessoryView:(UIView *)accessoryView;

/**
 JS回调事件
 
 @param event 事件名
 @param param 回调参数
 @param cbparam 原样回调参数
 */
- (void)callbackWithEvent:(NSString *)event param:(id)param cbparam:(id)cbparam completionHandler:(void (^)(id, NSError *))completionHandler;

/**
 JS回调函数

 @param fun 函数名
 @param params 参数，允许为nilh或多个
 */
- (void)callbakJSWithFun:(NSString *)fun params:(NSArray *)params completionHandler:(void (^)(id, NSError *))completionHandler;

/**
 执行JS
 @param javaScriptString 脚本字符串
 @param completionHandler 执行完后回调
 */
- (void)evaluateJavaScript:(NSString *)javaScriptString completionHandler:(void (^)(id obj, NSError *error))completionHandler;

@end
