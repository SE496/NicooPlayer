//
//  NicooPlayerView.swift
//  NicooPlayer
//
//  Created by 小星星 on 2018/6/19.
//

import UIKit
import AVFoundation
import AVKit
import SnapKit
import MediaPlayer
import MBProgressHUD

 public protocol NicooCustomMuneDelegate: class {
    /// 自定义右上角按钮点击操作
    func showCustomMuneView() -> UIView?
}

public protocol NicooPlayerDelegate: class {
    
    /// 代理在外部处理网络问题
    func retryToPlayVideo(_ videoModel: NicooVideoModel?, _ fatherView: UIView?)
   
    /// 当前播放的视频播放完成时调用
    ///
    /// - Parameters:
    ///   - videoModel: 当前播放完的本地视频的Model
    ///   - isPlayingDownLoadFile: 是否是播放的已下载视频
    func currentVideoPlayToEnd(_ videoModel: NicooVideoModel?, _ isPlayingDownLoadFile: Bool)
}

public extension NicooPlayerDelegate {
    func currentVideoPlayToEnd(_ videoModel: NicooVideoModel?, _ isPlayingDownLoadFile: Bool) {
    }
}

/// 播放状态枚举
///
/// - Failed: 失败
/// - ReadyToPlay: 将要播放
/// - Unknown: 未知
/// - Buffering: 正在缓冲
/// - Playing: 播放
/// - Pause: 暂停

public enum PlayerStatus {
    case Failed
    case ReadyToPlay
    case Unknown
    case Buffering
    case Playing
    case Pause
}

/// 滑动手势的方向
enum PanDirection: Int {
    case PanDirectionHorizontal     //水平
    case PanDirectionVertical       //上下
}

/// 播放器View
open class NicooPlayerView: UIView {
    
    static let kCustomViewTag = 6666
    
    // MARK: - Public Var
    /// 播放状态
    public var playerStatu: PlayerStatus? {
        didSet {
            if playerStatu == PlayerStatus.Playing {
                playControllViewEmbed.playOrPauseBtn.isSelected = true
                player?.play()
                if self.subviews.contains(pauseButton) {
                    pauseButton.isHidden = true
                    pauseButton.removeFromSuperview()
                }
            }else if playerStatu == PlayerStatus.Pause {
                player?.pause()
                playControllViewEmbed.playOrPauseBtn.isSelected = false
                if !self.subviews.contains(pauseButton) {
                    self.insertSubview(pauseButton, aboveSubview: playControllViewEmbed)
                    pauseButton.isHidden = false
                    layoutPauseButton()
                }
            }
        }
    }
    /// 是否是全屏
    public var isFullScreen: Bool? = false {
        didSet {  // 监听全屏切换， 改变返回按钮，全屏按钮的状态和图片
            playControllViewEmbed.closeButton.isSelected = isFullScreen!
            playControllViewEmbed.fullScreenBtn.isSelected = isFullScreen!
            playControllViewEmbed.fullScreen = isFullScreen!
            if let view = UIApplication.shared.value(forKey: "statusBar") as? UIView {  // 状态栏变化
                if !isFullScreen! {
                    view.alpha = 1.0
                } else {  // 全频
                    if playControllViewEmbed.barIsHidden! { // 状态栏
                        view.alpha = 0
                    } else {
                        view.alpha = 1.0
                    }
                }
            }
            if !isFullScreen! {
                /// 非全屏状态下，移除自定义视图
                if let customView = self.viewWithTag(NicooPlayerView.kCustomViewTag) {
                    customView.removeFromSuperview()
                }
                playControllViewEmbed.munesButton.isHidden = true
                playControllViewEmbed.closeButton.snp.updateConstraints { (make) in
                    make.width.equalTo(5)
                }
                playControllViewEmbed.closeButton.isEnabled = false
            }else {
                playControllViewEmbed.closeButton.snp.updateConstraints { (make) in
                    make.width.equalTo(40)
                }
                playControllViewEmbed.closeButton.isEnabled = true
                if customViewDelegate != nil {
                    playControllViewEmbed.munesButton.isHidden = false
                }else {
                    playControllViewEmbed.munesButton.isHidden = true
                }
            }
        }
    }
    public weak var delegate: NicooPlayerDelegate?
    public weak var customViewDelegate: NicooCustomMuneDelegate?
    /// 本地视频播放时回调视频播放进度
    public var playLocalFileVideoCloseCallBack:((_ playValue: Float) -> Void)?
    
    
    // MARK: - Private Var
    
    /// 视频截图
    private(set)  var imageGenerator: AVAssetImageGenerator?  // 用来做预览，目前没有预览的需求
    /// 当前屏幕状态
    private var currentOrientation: UIInterfaceOrientation?
    /// 保存传入的播放时间起点
    private var playTimeSince: Float = 0
    /// 当前播放进度
    private var playedValue: Float = 0 {  // 播放进度
        didSet {
            if oldValue < playedValue {  // 表示在播放中
                if playControllViewEmbed.loadingView.isAnimating {
                    playControllViewEmbed.loadingView.stopAnimating()
                }
                if !playControllViewEmbed.panGesture.isEnabled && !playControllViewEmbed.screenIsLock! {
                    playControllViewEmbed.panGesture.isEnabled = true
                }
                self.hideLoadingHud()
                if self.subviews.contains(loadedFailedView) {
                    self.loadedFailedView.removeFromSuperview()
                }
            }
        }
    }
    /// 父视图
    private weak var fatherView: UIView?  {
        willSet {
            if newValue != nil {
                for view in (newValue?.subviews)! {
                    if view.tag != 0 {                  // 这里用于cell播放时，隐藏播放按钮
                        view.isHidden = true
                    }
                }
            }
        }
        didSet {
            if oldValue != nil && oldValue != fatherView {
                for view in (oldValue?.subviews)! {     // 当前播放器的tag为0
                    if view.tag != 0 {
                        view.isHidden = false           // 显示cell上的播放按钮
                    }
                }
            }
            if fatherView != nil && !(fatherView?.subviews.contains(self))! {
                fatherView?.addSubview(self)
            }
            
        }
    }
    
    /// 嵌入式播放控制View
    private lazy var playControllViewEmbed: NicooPlayerControlView = {
        let playControllView = NicooPlayerControlView(frame: self.bounds, fullScreen: false)
        playControllView.delegate = self
        return playControllView
    }()
    /// 显示拖动进度的显示
    private lazy var draggedProgressView: UIView = {
        let view = UIView()
        view.backgroundColor =  UIColor(white: 0.2, alpha: 0.4)
        view.addSubview(self.draggedStatusButton)
        view.addSubview(self.draggedTimeLable)
        view.layer.cornerRadius = 3
        return view
    }()
    private lazy var draggedStatusButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(NicooImgManager.foundImage(imageName: "forward"), for: .normal)
        button.setImage(NicooImgManager.foundImage(imageName: "backward"), for: .selected)
        button.isUserInteractionEnabled = false
        return button
    }()
    private lazy var draggedTimeLable: UILabel = {
        let lable = UILabel()
        lable.textColor = UIColor.white
        lable.font = UIFont.systemFont(ofSize: 13)
        lable.textAlignment = .center
        return lable
    }()
    /// 暂停按钮
    private lazy var pauseButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(NicooImgManager.foundImage(imageName: "pause"), for: .normal)
        button.backgroundColor = UIColor(white: 0.0, alpha: 0.90)
        button.layer.cornerRadius = 27.5
        button.layer.masksToBounds = true
        button.addTarget(self, action: #selector(pauseButtonClick), for: .touchUpInside)
        return button
    }()
    /// 网络不好时提示
    private lazy var loadedFailedView: NicooLoadedFailedView = {
        let failedView = NicooLoadedFailedView(frame: self.bounds)
        failedView.backgroundColor = UIColor(white: 0.2, alpha: 0.5)
        return failedView
    }()
    
    /// 网络视频链接(每次对链接赋值，都会重置播放器)
    private var playUrl: URL? {
        didSet {
            if let videoUrl = playUrl {
                resetPlayerResource(videoUrl)
            }
        }
    }
    /// 本地视频链接
    private var fileUrlString: String?
    /// 视频名称
    private var videoName: String? {
        didSet {
            if videoName != nil {
                playControllViewEmbed.videoNameLable.text = String(format: "%@", videoName!)
            }
        }
    }
    /// 亮度显示
    private var brightnessSlider: NicooBrightnessView = {
        let brightView = NicooBrightnessView(frame: CGRect(x: 0, y: 0, width: 155, height: 155))
        return brightView
    }()
    private lazy var volumeView: MPVolumeView = {
        let volumeV = MPVolumeView()
        volumeV.showsVolumeSlider = false
        volumeV.showsRouteButton = false
        volumeSlider = nil //每次获取要将之前的置为nil
        for view in volumeV.subviews {
            if view.classForCoder.description() == "MPVolumeSlider" {
                if let vSlider = view as? UISlider {
                    volumeSlider = vSlider
                    volumeSliderValue = Float64(vSlider.value)
                }
                break
            }
        }
        return volumeV
    }()
    /// 进入后台前的屏幕状态
    private var beforeEnterBackgoundOrientation: UIInterfaceOrientation?   // 暂时没用到
    // 滑动手势的方向
    private var panDirection: PanDirection?
    // 记录拖动的值
    private var sumTime: CGFloat?
    /// 进度条滑动之前的播放状态，保证滑动进度后，恢复到滑动之前的播放状态
    private var beforeSliderChangePlayStatu: PlayerStatus?
    /// 加载进度
    private var loadedValue: Float = 0
    /// 视频总时长
    private var videoDuration: Float = 0
    /// 音量大小
    private var volumeSliderValue: Float64 = 0
    private var playerLayer: AVPlayerLayer?
    private var player: AVPlayer?
    private var avItem: AVPlayerItem?
    private var avAsset: AVAsset?
    /// 音量显示
    private var volumeSlider: UISlider?
    
    // MARK: - Life - Cycle
    
    deinit {
        print("播放器释放")
        NotificationCenter.default.removeObserver(self)
        self.avItem?.removeObserver(self, forKeyPath: "status")
        self.avItem?.removeObserver(self, forKeyPath: "loadedTimeRanges")
        self.avItem?.removeObserver(self, forKeyPath: "playbackBufferEmpty")
        self.avItem?.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
        orientationSupport = OrientationSupport.orientationPortrait
        destructPlayerResource()
    }
    public init(frame: CGRect, controlView: UIView? = nil) {
        super.init(frame: frame)
        self.backgroundColor = .black
        
        // 注册APP被挂起 + 进入前台通知
        NotificationCenter.default.addObserver(self, selector: #selector(NicooPlayerView.applicationResignActivity(_:)), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(NicooPlayerView.applicationBecomeActivity(_:)), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

// MARK: - Open Func (api)

extension NicooPlayerView {
    
    /// 播放视频
    ///
    /// - Parameters:
    ///   - videoUrl: 视频链接
    ///   - videoName: 视频名称（非必传）
    ///   - containerView: 视频父视图
    open func playVideo(_ videoUrl: URL?, _ videoName: String? = nil, _ containerView: UIView?) {
        // 这里有个视频解密过程
        playVideoWith(videoUrl, videoName: videoName, containView: containerView)
        
    }
    
    ///   从某个时间点开始播放视频
    ///
    /// - Parameters:
    ///   - videoUrl: 视频连接
    ///   - videoTitle: 视屏名称
    ///   - containerView: 视频父视图
    ///   - lastPlayTime: 上次播放的时间点
    open func replayVideo(_ videoUrl: URL?, _ videoTitle: String? = nil, _ containerView: UIView?, _ lastPlayTime: Float) {
        self.playVideo(videoUrl, videoTitle, containerView)
        guard let avItem = self.avItem else {
            return
        }
        self.playTimeSince = lastPlayTime      // 保存播放起点，在网络断开时，点击重试，可以找到起点
        self.playerStatu = PlayerStatus.Pause
        if self.playControllViewEmbed.loadingView.isAnimating {
            self.playControllViewEmbed.loadingView.stopAnimating()
        }
        showLoadingHud()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let lastPositionValue = CMTimeMakeWithSeconds(Float64(lastPlayTime), (avItem.duration.timescale))
            self.playSinceTime(lastPositionValue)
        }
        
    }
    
    /// 直接全屏播放，思路就是：直接将播放器添加到父视图上，：1.播放视频，2：屏幕强制旋转到右侧，3.隐藏全屏切换按钮 ，4.更换返回按钮事件为移除播放器
    ///
    /// - Parameters:
    ///   - videoUrl: 视屏URL
    ///   - videoTitle: 视屏名称
    ///   - containerView: 父视图
    ///   - sinceTime: 从某个时间点开始播放
    open func playLocalVideoInFullscreen(_ filePathUrl: String?, _ videoTitle: String? = nil, _ containerView: UIView?, sinceTime: Float? = nil) {
        playDownFileWith(filePathUrl, videoTitle, containerView, sinceTime: sinceTime)
    }
    
    /// 改变播放器的父视图
    ///
    /// - Parameter containerView: New fatherView
    open func changeVideoContainerView(_ containerView: UIView) {
        fatherView = containerView
        layoutAllPageSubviews()        //改变了父视图，需要重新布局
    }
    
    /// 获取当前播放时间点 + 视频总时长
    ///
    /// - Returns: 返回当前视频播放的时间,和视频总时长 （单位: 秒）
    open func getNowPlayPositionTimeAndVideoDuration() -> [Float] {
        return [self.playedValue, self.videoDuration]
    }
    
    /// 获取当前已缓存的时间点
    ///
    /// - Returns: 返回当前已缓存的时间 （单位: 秒）
    open func getLoadingPositionTime() -> Float {
        return self.loadedValue
    }
}

// MARK: - Private Funcs (私有方法)

private extension NicooPlayerView {
    
    private func playVideoWith(_ url: URL?, videoName: String?, containView: UIView?) {
        // 👇三个属性的设置顺序很重要
        self.playUrl = url   // 判断视频链接是否更改，更改了就重置播放器
        self.videoName = videoName      // 视频名称
        
        if !isFullScreen! {
            fatherView = containView // 更换父视图时
        }
        layoutAllPageSubviews()
        playerStatu = PlayerStatus.Playing // 初始状态为播放
        listenTothePlayer()
        addUserActionBlock()
    }
    
    /// 播放本地视频文件 : 1.标注为播放本地文件。 2.初始化播放器，播放视频）。 3.根据标记改变屏幕支持方向。4.隐藏全屏按钮 5.强制横屏
    ///
    /// - Parameters:
    ///   - filePathUrl: 本地连接
    ///   - videoTitle: 视频名称
    ///   - containerView: 父视图
    ///   - sinceTime: 从某个时间开始播放
    
    private func playDownFileWith(_ filePathUrl: String?, _ videoTitle: String?, _ containerView: UIView?, sinceTime: Float? = nil) {
        playControllViewEmbed.playLocalFile = true  // 声明直接就进入全屏播放               ------------------   1
        fileUrlString = filePathUrl              // 保存本地文件URL
        /// 重置播放源
        let url = URL(fileURLWithPath: filePathUrl ?? "")
        // 👇三个属性的设置顺序很重要
        self.playUrl = url                // 判断视频链接是否更改，更改了就重置播放器        // ------------------------- 2  + 3
        self.videoName = videoTitle      // 视频名称
        if !isFullScreen! {
            fatherView = containerView // 更换父视图时
        }
        playControllViewEmbed.loadedProgressView.setProgress(1, animated: false)
        
        
        self.playControllViewEmbed.fullScreenBtn.isHidden = true                      // --------------------------- 4
        
        layoutAllPageSubviews()
        playerStatu = PlayerStatus.Playing // 初始状态为播放
        listenTothePlayer()
        addUserActionBlock()
        playControllViewEmbed.closeButton.setImage(NicooImgManager.foundImage(imageName: "back"), for: .normal)
        playControllViewEmbed.closeButton.snp.updateConstraints({ (make) in
            make.width.equalTo(40)
        })
        interfaceOrientation(UIInterfaceOrientation.landscapeRight)                       // ---------------------------- 5
        /// 播放记录
        if let playLastTime = sinceTime, playLastTime > 1 {
            self.playTimeSince = playLastTime      // 保存播放起点，在网络断开时，点击重试，可以找到起点
            self.playerStatu = PlayerStatus.Pause
            guard let avItem = self.avItem else{return}
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let lastPositionValue = CMTimeMakeWithSeconds(Float64(playLastTime), (avItem.duration.timescale))
                self.playSinceTime(lastPositionValue)
            }
        }
        
    }
    
    private func showLoadingHud() {
        let hud = MBProgressHUD.showAdded(to: self, animated: false)
        hud?.labelText = "正在加载..."
        hud?.labelFont = UIFont.systemFont(ofSize: 15)
        hud?.opacity = 0.0
    }
    
    private func hideLoadingHud() {
        MBProgressHUD.hideAllHUDs(for: self, animated: false)
    }
    
    /// 初始化播放源
    ///
    /// - Parameter videoUrl: 视频链接
    private func setUpPlayerResource(_ videoUrl: URL) {
        avAsset = AVAsset(url: videoUrl)
        avItem = AVPlayerItem(asset: self.avAsset!)
        player = AVPlayer(playerItem: self.avItem!)
        playerLayer = AVPlayerLayer(player: self.player!)
        self.layer.addSublayer(playerLayer!)
        self.addSubview(playControllViewEmbed)
        playControllViewEmbed.timeSlider.value = 0
        playControllViewEmbed.loadedProgressView.setProgress(0, animated: false)
        NSObject.cancelPreviousPerformRequests(withTarget: playControllViewEmbed, selector: #selector(NicooPlayerControlView.autoHideTopBottomBar), object: nil)
        playControllViewEmbed.perform(#selector(NicooPlayerControlView.autoHideTopBottomBar), with: nil, afterDelay: 5)
        
        if playControllViewEmbed.playLocalFile! {       // 播放本地视频时只支持左右
            orientationSupport = OrientationSupport.orientationLeftAndRight
        } else {
            showLoadingHud()      /// 网络视频才显示菊花
            orientationSupport = OrientationSupport.orientationAll
        }
    }
    
    /// 重置播放器
    ///
    /// - Parameter videoUrl: 视频链接
    private func resetPlayerResource(_ videoUrl: URL) {
        self.avAsset = nil
        self.avItem = nil
        self.player?.replaceCurrentItem(with: nil)
        self.player = nil
        self.playerLayer?.removeFromSuperlayer()
        self.layer.removeAllAnimations()
        startReadyToPlay()
        setUpPlayerResource(videoUrl)
    }
    
    /// 销毁播放器源
    private func destructPlayerResource() {
        self.avAsset = nil
        self.avItem = nil
        self.player?.replaceCurrentItem(with: nil)
        self.player = nil
        self.playerLayer?.removeFromSuperlayer()
        self.layer.removeAllAnimations()
    }
    
    /// 从某个点开始播放
    ///
    /// - Parameter time: 要从开始的播放起点
    private func playSinceTime(_ time: CMTime) {
        if CMTIME_IS_VALID(time) {
            avItem?.seek(to: time, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero, completionHandler: { [weak self] (finish) in
                if finish {
                    self?.playerStatu = PlayerStatus.Playing
                    self?.hideLoadingHud()
                }
            })
            return
        }else {
            self.hideLoadingHud()
            //  这里讲网络加载失败的情况代理出去，在外部处理
            //delegate?.playerLoadedVideoUrlFailed()
            if !playControllViewEmbed.playLocalFile! {  /// 非本地文件播放才显示网络失败
                showLoadedFailedView()
            }
        }
    }
    
    /// 获取系统音量控件 及大小
    private func configureSystemVolume() {
        let volumeView = MPVolumeView()
        self.volumeSlider = nil //每次获取要将之前的置为nil
        for view in volumeView.subviews {
            if view.classForCoder.description() == "MPVolumeSlider" {
                if let vSlider = view as? UISlider {
                    volumeSlider = vSlider
                    volumeSliderValue = Float64(vSlider.value)
                }
                break
            }
        }
    }
    
    // MARK: - addNotificationAndObserver
    private func addNotificationAndObserver() {
        guard let avItem = self.avItem else {return}
        ///注册通知之前，需要先移除对应的通知，因为添加多此观察，方法会调用多次
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(playToEnd(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: avItem)
        avItem.addObserver(self, forKeyPath: "status", options: NSKeyValueObservingOptions.new, context: nil)
        avItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: NSKeyValueObservingOptions.new, context: nil)
        avItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: NSKeyValueObservingOptions.new, context: nil)
        avItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: NSKeyValueObservingOptions.new, context: nil)
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        // 注册屏幕旋转通知
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: UIDevice.current)
        NotificationCenter.default.addObserver(self, selector: #selector(NicooPlayerView.orientChange(_:)), name: NSNotification.Name.UIDeviceOrientationDidChange, object: UIDevice.current)
    }
    
    // MARK: - 返回，关闭，全屏，播放，暂停,重播,音量，亮度，进度拖动 - UserAction
    @objc func pauseButtonClick() {
        self.playerStatu = PlayerStatus.Playing
    }
    
    // MARK: - User Action - Block
    private func addUserActionBlock() {
        // MARK: - 返回，关闭
        playControllViewEmbed.closeButtonClickBlock = { [weak self] (sender) in
            guard let strongSelf = self else {return}
            if strongSelf.isFullScreen! {
                if strongSelf.playControllViewEmbed.playLocalFile! {   // 直接全屏播放本地视频
                    strongSelf.removeFromSuperview()
                    // strongSelf.destructPlayerResource()
                    orientationSupport = OrientationSupport.orientationPortrait
                    strongSelf.playLocalFileVideoCloseCallBack?(self?.playedValue ?? 0.0)
                    strongSelf.interfaceOrientation(UIInterfaceOrientation.portrait)
                    
                } else {
                    strongSelf.interfaceOrientation(UIInterfaceOrientation.portrait)
                }
            }else {                                                    // 非全屏状态，停止播放，移除播放视图
                print("非全屏状态，停止播放，移除播放视图")
            }
        }
        // MARK: - 全屏
        playControllViewEmbed.fullScreenButtonClickBlock = { [weak self] (sender) in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.isFullScreen! {
                strongSelf.interfaceOrientation(UIInterfaceOrientation.portrait)
            }else{
                strongSelf.interfaceOrientation(UIInterfaceOrientation.landscapeRight)
            }
        }
        // MARK: - 播放暂停
        playControllViewEmbed.playOrPauseButtonClickBlock = { [weak self] (sender) in
            if self?.playerStatu == PlayerStatus.Playing {
                self?.playerStatu = PlayerStatus.Pause
            }else if self?.playerStatu == PlayerStatus.Pause {
                self?.playerStatu = PlayerStatus.Playing
            }
        }
        // MARK: - 锁屏
        playControllViewEmbed.screenLockButtonClickBlock = { [weak self] (sender) in
            guard let strongSelf = self else { return }
            if sender.isSelected {
                orientationSupport = OrientationSupport.orientationLeftAndRight
            }else {
                if strongSelf.playControllViewEmbed.playLocalFile! {
                    orientationSupport = OrientationSupport.orientationLeftAndRight
                } else {
                    orientationSupport = OrientationSupport.orientationAll
                }
            }
        }
        // MARK: - 重播
        playControllViewEmbed.replayButtonClickBlock = { [weak self] (_) in
            self?.avItem?.seek(to: kCMTimeZero)
            self?.startReadyToPlay()
            self?.playerStatu = PlayerStatus.Playing
        }
        // MARK: - 分享按钮点击
        playControllViewEmbed.muneButtonClickBlock = { [weak self] (_) in
            guard let strongSelf = self else {
                return
            }
            /// 通过代理回调设置自定义覆盖操作视图
            if let customMuneView = strongSelf.customViewDelegate?.showCustomMuneView() {
                
                customMuneView.tag = NicooPlayerView.kCustomViewTag /// 给外来视图打标签，便于移除
                
                if !strongSelf.subviews.contains(customMuneView) {
                    strongSelf.addSubview(customMuneView)
                }
                customMuneView.snp.makeConstraints({ (make) in
                    if #available(iOS 11.0, *) {
                        make.edges.equalTo(strongSelf.safeAreaLayoutGuide.snp.edges)
                    } else {
                        make.edges.equalToSuperview()
                    }
                })
            }
            
        }
        // MARK: - 音量，亮度，进度拖动
        self.configureSystemVolume()             // 获取系统音量控件   可以选择自定义，效果会比系统的好
        
        playControllViewEmbed.pangeustureAction = { [weak self] (sender) in
            guard let avItem = self?.avItem  else {return}                     // 如果 avItem 不存在，手势无响应
            guard let strongSelf = self else {return}
            let locationPoint = sender.location(in: strongSelf.playControllViewEmbed)
            /// 根据上次和本次移动的位置，算出一个速率的point
            let veloctyPoint = sender.velocity(in: strongSelf.playControllViewEmbed)
            switch sender.state {
            case .began:
                
                NSObject.cancelPreviousPerformRequests(withTarget: strongSelf.playControllViewEmbed, selector: #selector(NicooPlayerControlView.autoHideTopBottomBar), object: nil)    // 取消5秒自动消失控制栏
                strongSelf.playControllViewEmbed.barIsHidden = false
                
                // 使用绝对值来判断移动的方向
                let x = fabs(veloctyPoint.x)
                let y = fabs(veloctyPoint.y)
                
                if x > y {                       //水平滑动
                    if !strongSelf.playControllViewEmbed.replayContainerView.isHidden {  // 锁屏状态下播放完成,解锁后，滑动
                        strongSelf.startReadyToPlay()
                        strongSelf.playControllViewEmbed.screenIsLock = false
                    }
                    strongSelf.panDirection = PanDirection.PanDirectionHorizontal
                    strongSelf.beforeSliderChangePlayStatu = strongSelf.playerStatu  // 拖动开始时，记录下拖动前的状态
                    strongSelf.playerStatu = PlayerStatus.Pause                // 拖动开始，暂停播放
                    strongSelf.pauseButton.isHidden = true                     // 拖动时隐藏暂停按钮
                    strongSelf.sumTime = CGFloat(avItem.currentTime().value)/CGFloat(avItem.currentTime().timescale)
                    if !strongSelf.subviews.contains(strongSelf.draggedProgressView) {
                        strongSelf.addSubview(strongSelf.draggedProgressView)
                        strongSelf.layoutDraggedContainers()
                    }
                    
                }else if x < y {
                    strongSelf.panDirection = PanDirection.PanDirectionVertical
                    
                    if locationPoint.x > strongSelf.playControllViewEmbed.bounds.size.width/2 && locationPoint.y < strongSelf.playControllViewEmbed.bounds.size.height - 40 {  // 触摸点在视图右边，控制音量
                        // 如果需要自定义 音量控制显示，在这里添加自定义VIEW
                        if !strongSelf.subviews.contains(strongSelf.volumeView) {
                            strongSelf.addSubview(strongSelf.volumeView)
                            strongSelf.volumeView.snp.makeConstraints({ (make) in
                                make.center.equalToSuperview()
                                make.width.equalTo(155)
                                make.height.equalTo(155)
                            })
                        }
                        
                        
                    }else if locationPoint.x < strongSelf.playControllViewEmbed.bounds.size.width/2 && locationPoint.y < strongSelf.playControllViewEmbed.bounds.size.height - 40 {
                        if !strongSelf.subviews.contains(strongSelf.brightnessSlider) {
                            strongSelf.addSubview(strongSelf.brightnessSlider)
                            strongSelf.brightnessSlider.snp.makeConstraints({ (make) in
                                make.center.equalToSuperview()
                                make.width.equalTo(155)
                                make.height.equalTo(155)
                            })
                        }
                    }
                }
                break
            case .changed:
                switch strongSelf.panDirection! {
                case .PanDirectionHorizontal:
                    let durationValue = CGFloat(avItem.duration.value)/CGFloat(avItem.duration.timescale)
                    let draggedValue = strongSelf.horizontalMoved(veloctyPoint.x)
                    let positionValue = CMTimeMakeWithSeconds(Float64(durationValue) * Float64(draggedValue), (avItem.duration.timescale))
                    avItem.seek(to: positionValue, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
                    break
                case .PanDirectionVertical:
                    if locationPoint.x > strongSelf.playControllViewEmbed.bounds.size.width/2 && locationPoint.y < strongSelf.playControllViewEmbed.bounds.size.height - 40 {
                        strongSelf.veloctyMoved(veloctyPoint.y, true)
                    }else if locationPoint.x < strongSelf.playControllViewEmbed.bounds.size.width/2 && locationPoint.y < strongSelf.playControllViewEmbed.bounds.size.height - 40 {
                        strongSelf.veloctyMoved(veloctyPoint.y, false)
                    }
                    break
                }
                break
            case .ended:
                switch strongSelf.panDirection! {
                case .PanDirectionHorizontal:
                    let position = CGFloat(avItem.duration.value)/CGFloat(avItem.duration.timescale)
                    let sliderValue = strongSelf.sumTime!/position
                    if !strongSelf.playControllViewEmbed.loadingView.isAnimating {
                        strongSelf.playControllViewEmbed.loadingView.startAnimating()
                    }
                    let po = CMTimeMakeWithSeconds(Float64(position) * Float64(sliderValue), (avItem.duration.timescale))
                    avItem.seek(to: po, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
                    /// 拖动完成，sumTime置为0 回到之前的播放状态，如果播放状态为
                    strongSelf.sumTime = 0
                    strongSelf.pauseButton.isHidden = false
                    strongSelf.playerStatu = strongSelf.beforeSliderChangePlayStatu!
                    
                    //进度拖拽完成，5庙后自动隐藏操作栏
                    strongSelf.playControllViewEmbed.perform(#selector(NicooPlayerControlView.autoHideTopBottomBar), with: nil, afterDelay: 5)
                    
                    if strongSelf.subviews.contains(strongSelf.draggedProgressView) {
                        strongSelf.draggedProgressView.removeFromSuperview()
                    }
                    break
                case .PanDirectionVertical:
                    //进度拖拽完成，5庙后自动隐藏操作栏
                    strongSelf.playControllViewEmbed.perform(#selector(NicooPlayerControlView.autoHideTopBottomBar), with: nil, afterDelay: 5)
                    if locationPoint.x < strongSelf.playControllViewEmbed.bounds.size.width/2 {    // 触摸点在视图左边 隐藏屏幕亮度
                        strongSelf.brightnessSlider.removeFromSuperview()
                    } else {
                        strongSelf.volumeView.removeFromSuperview()
                    }
                    break
                }
                break
                
            case .possible:
                break
            case .failed:
                break
            case .cancelled:
                break
            }
        }
    }
    
    // MARK: - 水平拖动进度手势
    private func horizontalMoved(_ moveValue: CGFloat) ->CGFloat {
        guard var sumValue = self.sumTime else {
            return 0
        }
        // 限定sumTime的范围
        guard let avItem = self.avItem else {
            return 0
        }
        // 这里可以调整拖动灵敏度， 数字（99）越大，灵敏度越低
        sumValue += moveValue / 99
        
        let totalMoveDuration = CGFloat(avItem.duration.value)/CGFloat(avItem.duration.timescale)
        
        if sumValue > totalMoveDuration {
            sumValue = totalMoveDuration
        }
        if sumValue < 0 {
            sumValue = 0
        }
        let dragValue = sumValue / totalMoveDuration
        // 拖动时间展示
        let allTimeString =  self.formatTimDuration(position: Int(sumValue), duration: Int(totalMoveDuration))
        let draggedTimeString = self.formatTimPosition(position: Int(sumValue), duration: Int(totalMoveDuration))
        self.draggedTimeLable.text = String(format: "%@|%@", draggedTimeString,allTimeString)
        
        self.draggedStatusButton.isSelected = moveValue < 0
        self.playControllViewEmbed.positionTimeLab.text = self.formatTimPosition(position: Int(sumValue), duration: Int(totalMoveDuration))
        self.playControllViewEmbed.timeSlider.value = Float(dragValue)
        self.sumTime = sumValue
        return dragValue
        
    }
    
    // MARK: - 上下拖动手势
    private func veloctyMoved(_ movedValue: CGFloat, _ isVolume: Bool) {
        
        if isVolume {
            volumeSlider?.value  -= Float(movedValue/10000)
            print("self.volumeSliderValue== \(self.volumeSliderValue)")
        }else {
            UIScreen.main.brightness  -= movedValue/10000
            self.brightnessSlider.updateBrightness(UIScreen.main.brightness)
        }
    }
    
    // MARK: - 播放结束
    /// 播放结束时调用
    ///
    /// - Parameter sender: 监听播放结束
    @objc func playToEnd(_ sender: Notification) {
        self.playerStatu = PlayerStatus.Pause //同时为暂停状态
        self.pauseButton.isHidden = true
        playControllViewEmbed.replayContainerView.isHidden = false
        playControllViewEmbed.barIsHidden = true
        playControllViewEmbed.topControlBarView.isHidden = false   //单独显示顶部操作栏
        playControllViewEmbed.singleTapGesture.isEnabled = false
        playControllViewEmbed.doubleTapGesture.isEnabled = false
        playControllViewEmbed.panGesture.isEnabled = false
        playControllViewEmbed.timeSlider.value = 0
        playControllViewEmbed.screenLockButton.isHidden = true
        playControllViewEmbed.loadedProgressView.setProgress(0, animated: false)
        playControllViewEmbed.loadingView.stopAnimating()
        if let item = sender.object as? AVPlayerItem {   /// 这里要区分介乎的视频是哪一个
            if let asset = item.asset as? AVURLAsset {
                let model = NicooVideoModel(videoName: self.videoName, videoUrl: asset.url.absoluteString, videoPlaySinceTime: self.playTimeSince)
                delegate?.currentVideoPlayToEnd(model, playControllViewEmbed.playLocalFile!)
            }
        }
    }
    
    // MARK: - 开始播放准备
    private func startReadyToPlay() {
        playControllViewEmbed.barIsHidden = false
        playControllViewEmbed.replayContainerView.isHidden = true
        playControllViewEmbed.singleTapGesture.isEnabled = true
        playControllViewEmbed.doubleTapGesture.isEnabled = true
        playControllViewEmbed.panGesture.isEnabled = true
        self.loadedFailedView.removeFromSuperview()
    }
    
    // MARK: - 网络提示显示
    private func showLoadedFailedView() {
        self.addSubview(loadedFailedView)
        loadedFailedView.retryButtonClickBlock = { [weak self] (sender) in
            let model = NicooVideoModel(videoName: self?.videoName, videoUrl: self?.playUrl?.absoluteString, videoPlaySinceTime: (self?.playTimeSince)!)
            self?.delegate?.retryToPlayVideo(model, self?.fatherView)
        }
        loadedFailedView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    
    // MARK: - InterfaceOrientation - Change (屏幕方向改变)
    
    @objc func orientChange(_ sender: Notification) {
        let orirntation = UIApplication.shared.statusBarOrientation
        if  orirntation == UIInterfaceOrientation.landscapeLeft || orirntation == UIInterfaceOrientation.landscapeRight  {
            isFullScreen = true
            self.removeFromSuperview()
            UIApplication.shared.keyWindow?.addSubview(self)
            UIView.animate(withDuration: 0.2, delay: 0, options: UIViewAnimationOptions.transitionCurlUp, animations: {
                self.snp.makeConstraints({ (make) in
                    make.edges.equalTo(UIApplication.shared.keyWindow!)
                })
                if #available(iOS 11.0, *) {                           // 横屏播放时，适配X
                    if UIDevice.current.isiPhoneX() {
                        self.playControllViewEmbed.snp.remakeConstraints({ (make) in
                            make.leading.equalTo(self.safeAreaLayoutGuide.snp.leading).offset(25)
                            make.trailing.equalTo(self.safeAreaLayoutGuide.snp.trailing).offset(-25)
                            make.top.equalTo(self.safeAreaLayoutGuide.snp.top)
                            make.bottom.equalToSuperview()
                        })
                    }
                }
                self.layoutIfNeeded()
                self.playControllViewEmbed.layoutIfNeeded()
            }, completion: nil)
            
        } else if orirntation == UIInterfaceOrientation.portrait {
            if !self.playControllViewEmbed.screenIsLock! { // 非锁品状态下
                isFullScreen = false
                self.removeFromSuperview()
                if let containerView = self.fatherView {
                    containerView.addSubview(self)
                    UIView.animate(withDuration: 0.2, delay: 0, options: UIViewAnimationOptions.curveLinear, animations: {
                        self.snp.makeConstraints({ (make) in
                            make.edges.equalTo(containerView)
                        })
                        if #available(iOS 11.0, *) {         // 竖屏播放时，适配X
                            if UIDevice.current.isiPhoneX() {
                                self.playControllViewEmbed.snp.makeConstraints({ (make) in
                                    make.edges.equalToSuperview()
                                })
                            }
                        }
                        self.layoutIfNeeded()
                        self.playControllViewEmbed.layoutIfNeeded()
                    }, completion: nil)
                }
            }
        }
    }
    
    // MARK: - 强制横屏
    private func interfaceOrientation(_ orientation: UIInterfaceOrientation) {
        if orientation == UIInterfaceOrientation.landscapeRight || orientation == UIInterfaceOrientation.landscapeLeft {
            UIDevice.current.setValue(NSNumber(integerLiteral: UIInterfaceOrientation.landscapeRight.rawValue), forKey: "orientation")
        }else if orientation == UIInterfaceOrientation.portrait {
            UIDevice.current.setValue(NSNumber(integerLiteral: UIInterfaceOrientation.portrait.rawValue), forKey: "orientation")
            isFullScreen = false
        }
    }
    
    // MARK: - APP将要被挂起
    /// - Parameter sender: 记录被挂起前的播放状态，进入前台时恢复状态
    @objc func applicationResignActivity(_ sender: NSNotification) {
        self.beforeSliderChangePlayStatu = self.playerStatu  // 记录下进入后台前的播放状态
        self.playerStatu = PlayerStatus.Pause
    }
    
    // MARK: - APP进入前台，恢复播放状态
    @objc func applicationBecomeActivity(_ sender: NSNotification) {
        if let oldStatu = self.beforeSliderChangePlayStatu {
            self.playerStatu = oldStatu                      // 恢复进入后台前的播放状态
        }else {
            self.playerStatu = PlayerStatus.Pause
        }
    }
    
}

// MARK: - TZPlayerControlViewDelegate

extension NicooPlayerView: NicooPlayerControlViewDelegate {
    
    func sliderTouchBegin(_ sender: UISlider) {
        beforeSliderChangePlayStatu = playerStatu
        playerStatu = PlayerStatus.Pause
        pauseButton.isHidden = true
    }
    
    func sliderTouchEnd(_ sender: UISlider) {
        guard let avItem = self.avItem else {
            return
        }
        let position = Float64 ((avItem.duration.value)/Int64(avItem.duration.timescale))
        let po = CMTimeMakeWithSeconds(Float64(position) * Float64(sender.value), (avItem.duration.timescale))
        avItem.seek(to: po, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
        pauseButton.isHidden = false
        playerStatu = beforeSliderChangePlayStatu
        if !playControllViewEmbed.loadingView.isAnimating {
            playControllViewEmbed.loadingView.startAnimating()
        }
        
    }
    
    func sliderValueChange(_ sender: UISlider) {
        guard let avItem = self.avItem else {
            return
        }
        let position = Float64 ((avItem.duration.value)/Int64(avItem.duration.timescale))
        let po = CMTimeMakeWithSeconds(Float64(position) * Float64(sender.value), (avItem.duration.timescale))
        avItem.seek(to: po, toleranceBefore: kCMTimeZero, toleranceAfter: kCMTimeZero)
    }
}

// MARK: - Listen To the Player (监听播放状态)

extension NicooPlayerView {
    
    /// 监听PlayerItem对象
    fileprivate func listenTothePlayer() {
        guard let avItem = self.avItem else {return}
        player?.addPeriodicTimeObserver(forInterval: CMTimeMake(Int64(1.0), Int32(1.0)), queue: nil, using: { [weak self] (time) in
            
            let timeScaleValue = Int64(avItem.currentTime().timescale) /// 当前时间
            let timeScaleDuration = Int64(avItem.duration.timescale)   /// 总时间
            
            if avItem.duration.value > 0 && avItem.currentTime().value > 0 {
                let value = avItem.currentTime().value / timeScaleValue  /// 当前播放时间
                let duration = avItem.duration.value / timeScaleDuration /// 视频总时长
                let playValue = Float(value)/Float(duration)
                
                if  let stringDuration = self?.formatTimDuration(position: Int(value), duration:Int(duration)), let stringValue = self?.formatTimPosition(position: Int(value), duration: Int(duration)) {
                    //self.playControllViewEmbed.positionTimeLab.text = stringValue
                    self?.playControllViewEmbed.timeSlider.value = playValue
                    self?.playControllViewEmbed.durationTimeLab.text = String(format: "%@/%@", stringValue, stringDuration)
                }
                self?.playedValue = Float(value)                                      // 保存播放进度
            }
        })
        addNotificationAndObserver()
    }
    /// KVO 监听播放状态
    override open func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let avItem = object as? AVPlayerItem else {
            return
        }
        if  keyPath == "status" {
            if avItem.status == AVPlayerItemStatus.readyToPlay {
                let duration = Float(avItem.duration.value)/Float(avItem.duration.timescale)
                let currentTime =  avItem.currentTime().value/Int64(avItem.currentTime().timescale)
                let durationHours = (Int(duration) / 3600) % 60
                if (durationHours != 0) {
                    playControllViewEmbed.durationTimeLab.snp.updateConstraints { (make) in
                        make.width.equalTo(122)
                    }
                    //                    playControllViewEmbed.positionTimeLab.snp.updateConstraints { (make) in
                    //                        make.width.equalTo(67)
                    //                    }
                }
                self.videoDuration = Float(duration)
                print("时长 = \(duration) S, 已播放 = \(currentTime) s")
            }else if avItem.status == AVPlayerItemStatus.unknown {
                //视频加载失败，或者未知原因
                // playerStatu = PlayerStatus.Unknow
                hideLoadingHud()
                
            }else if avItem.status == AVPlayerItemStatus.failed {
                print("PlayerStatus.failed")
                // 代理出去，在外部处理网络问题
                if playControllViewEmbed.loadingView.isAnimating {
                    playControllViewEmbed.loadingView.stopAnimating()
                }
                hideLoadingHud()
                if !playControllViewEmbed.playLocalFile! {  /// 非本地文件播放才显示网络失败
                    showLoadedFailedView()
                }
            }
        } else if keyPath == "loadedTimeRanges" {
            //监听缓存进度，根据时间来监听
            let timeRange = avItem.loadedTimeRanges
            let cmTimeRange = timeRange[0] as! CMTimeRange
            let startSeconds = CMTimeGetSeconds(cmTimeRange.start)
            let durationSeconds = CMTimeGetSeconds(cmTimeRange.duration)
            let timeInterval = startSeconds + durationSeconds                    // 计算总进度
            let totalDuration = CMTimeGetSeconds(avItem.duration)
            self.loadedValue = Float(timeInterval)                               // 保存缓存进度
            self.playControllViewEmbed.loadedProgressView.setProgress(Float(timeInterval/totalDuration), animated: true)
        } else if keyPath == "playbackBufferEmpty" {                     // 监听播放器正在缓冲数据
            
        } else if keyPath == "playbackLikelyToKeepUp" {                   //监听视频缓冲达到可以播放的状态
            if playControllViewEmbed.loadingView.isAnimating {
                playControllViewEmbed.loadingView.stopAnimating()
            }
        }
    }
    
}

// MARK: - LayoutPageSubviews (UI布局)

extension NicooPlayerView {
    private func layoutLocalPlayView(_ localView: UIView) {
        self.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.width.equalTo(localView.snp.height)
            make.height.equalTo(localView.snp.width)
        }
    }
    private func layoutAllPageSubviews() {
        layoutSelf()
        layoutPlayControllView()
    }
    private func layoutDraggedContainers() {
        layoutDraggedProgressView()
        layoutDraggedStatusButton()
        layoutDraggedTimeLable()
    }
    private func layoutSelf() {
        self.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    private func layoutPlayControllView() {
        playControllViewEmbed.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
    }
    private func layoutDraggedProgressView() {
        draggedProgressView.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.height.equalTo(70)
            make.width.equalTo(120)
        }
    }
    private func layoutDraggedStatusButton() {
        draggedStatusButton.snp.makeConstraints { (make) in
            make.centerX.equalToSuperview()
            make.top.equalTo(8)
            make.height.equalTo(30)
            make.width.equalTo(40)
        }
    }
    private func layoutDraggedTimeLable() {
        draggedTimeLable.snp.makeConstraints { (make) in
            make.leading.equalTo(8)
            make.trailing.equalTo(-8)
            make.bottom.equalToSuperview()
            make.top.equalTo(draggedStatusButton.snp.bottom)
        }
    }
    private func layoutPauseButton() {
        pauseButton.snp.makeConstraints { (make) in
            make.center.equalToSuperview()
            make.width.equalTo(55)
            make.height.equalTo(55)
        }
    }
    override open func layoutSubviews() {
        super.layoutSubviews()
        playerLayer?.frame = self.bounds
    }
}

// MARK: - 时间转换格式

extension NicooPlayerView {
    
    fileprivate func formatTimPosition(position: Int, duration:Int) -> String{
        guard position != 0 && duration != 0 else{
            return "00:00"
        }
        let positionHours = (position / 3600) % 60
        let positionMinutes = (position / 60) % 60
        let positionSeconds = position % 60
        let durationHours = (Int(duration) / 3600) % 60
        if (durationHours == 0) {
            return String(format: "%02d:%02d",positionMinutes,positionSeconds)
        }
        return String(format: "%02d:%02d:%02d",positionHours,positionMinutes,positionSeconds)
    }
    
    fileprivate func formatTimDuration(position: Int, duration:Int) -> String{
        guard  duration != 0 else{
            return "00:00"
        }
        let durationHours = (duration / 3600) % 60
        let durationMinutes = (duration / 60) % 60
        let durationSeconds = duration % 60
        if (durationHours == 0)  {
            return String(format: "%02d:%02d",durationMinutes,durationSeconds)
        }
        return String(format: "%02d:%02d:%02d",durationHours,durationMinutes,durationSeconds)
    }
}
