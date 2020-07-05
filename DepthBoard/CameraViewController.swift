/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Contains view controller code for previewing live-captured content.
*/

import UIKit
import AVFoundation
import CoreVideo
import MobileCoreServices
import Accelerate
import Photos
import VideoToolbox

@available(iOS 11.1, *)
class CameraViewController: UIViewController, AVCaptureDataOutputSynchronizerDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, AVCaptureFileOutputRecordingDelegate {
    
    private var fps: Int = 0
    private let cntFrames: Bool = false
    private let serialQueue = DispatchQueue(label: "SerialQueue")

    @objc func fire()
    {
        if(cntFrames) {
            serialQueue.sync {
                print(fps)
                fps = 0
            }
        }
    }
    
    func fileOutput(_ output: AVCaptureFileOutput,
                    didStartRecordingTo fileURL: URL,
                    from connections: [AVCaptureConnection]) {
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        var message:String!
        //将录制好的录像保存到照片库中
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL)
        }, completionHandler: { (isSuccess: Bool, error: Error?) in
            if isSuccess {
                message = "保存成功!"
            } else{
                message = "保存失败：\(error!.localizedDescription)"
            }
            
            DispatchQueue.main.async {
                //弹出提示框
                let alertController = UIAlertController(title: message, message: nil,
                                                        preferredStyle: .alert)
                let cancelAction = UIAlertAction(title: "确定", style: .cancel, handler: nil)
                alertController.addAction(cancelAction)
                self.present(alertController, animated: true, completion: nil)
            }
        })
    }
    
    var isRecording = false
    
    @IBOutlet weak var recordButton: UIButton!
    // MARK: - Properties
    
    @IBAction func onClickRecording(_ sender: Any) { //restart this trial
        clearAll()
        OpenCVWrapper.newWord()
    }
    
    @IBOutlet weak private var resumeButton: UIButton!
    
    @IBOutlet weak private var cameraUnavailableLabel: UILabel!
    
    @IBOutlet weak private var jetView: PreviewMetalView!
    
    // @IBOutlet weak private var depthSmoothingSwitch: UISwitch!
    
//    @IBOutlet weak private var mixFactorSlider: UISlider!
    
    @IBOutlet weak private var touchDepth: UILabel!
    
    
    private var captureDevice: AVCaptureDevice!
    
    let fileOutput = AVCaptureMovieFileOutput()
    
    
    var cv = OpenCVWrapper()
    
    
    
    private enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }
    
    private var setupResult: SessionSetupResult = .success
    
    private let session = AVCaptureSession()
    
//    let captureSession = AVCaptureSession()
    
    private var isSessionRunning = false
    
    // Communicate with the session and other session objects on this queue.
    private let sessionQueue = DispatchQueue(label: "session queue", attributes: [], autoreleaseFrequency: .workItem)
    private var videoDeviceInput: AVCaptureDeviceInput!
    
    private let dataOutputQueue = DispatchQueue(label: "video data queue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let depthDataOutput = AVCaptureDepthDataOutput()
    private var outputSynchronizer: AVCaptureDataOutputSynchronizer?
    
    private var audioDeviceInput: AVCaptureDeviceInput!
    private let audioDataOutput = AVCaptureAudioDataOutput()
    private let audioQueue = DispatchQueue(label: "audio queue", qos: .userInitiated,
                                           attributes: [], autoreleaseFrequency: .workItem)
    
    private let videoDepthMixer = VideoMixer()
    
    private let videoDepthConverter = DepthToJETConverter()
    
    private var renderingEnabled = true
    
    private let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInTrueDepthCamera],
                                                                               mediaType: .video,
                                                                               position: .front)
    
    private var statusBarOrientation: UIInterfaceOrientation = .portrait
    
    private var touchDetected = false
    
    private var touchCoordinates = CGPoint(x: 0, y: 0)
    
    @IBOutlet weak private var cloudView: PointCloudMetalView!
    
    // @IBOutlet weak private var cloudToJETSegCtrl: UISegmentedControl!
    
    @IBOutlet weak private var smoothDepthLabel: UILabel!
    
    private var lastScale = Float(1.0)
    
    private var lastScaleDiff = Float(0.0)
    
    private var lastZoom = Float(0.0)
    
    private var lastXY = CGPoint(x: 0, y: 0)
    
    private var JETEnabled = true
    
    private var viewFrameSize = CGSize()
    
    // whether to smooth noise etc.
    private let smoothChoice = true
    
    // private var autoPanningIndex = Int(0) // start with auto-panning on
    private var sentenceArray = [String]()
    private var sentenceLabel: UILabel?
    private var inputLabel: UILabel?
    private var blkLabel: UILabel?
    private var phrLabel: UILabel?
    private var modeLabel: UILabel?
    private var candWordsLabel = [UILabel]() // UILabel to hold candidate words
    private var curCandNum = 0
    private var curWords = [String]() //words for current sentence
    private var curPointer: Int = 0 // pointer to curWords
    private var matchY = 0, matchN = 0, selectY = 0, selectN = 0, undo = 0, del = 0;
    
    private func initWordsLabel() {
        for i in 0 ..< 5 {
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 140, height: labelHeight))
            label.center = CGPoint(x: xLabel + 2*labelHeight + 40, y: 750 - 140*i)
            label.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2));
            label.text = ""
            label.textAlignment = NSTextAlignment.center
            label.font = UIFont(name: "Courier", size: 20.0)
            label.textColor = UIColor.white
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor.white.cgColor
            candWordsLabel.append(label)
            self.view.addSubview(label)
        }
    }
    
    private var inputMode: Int = 1 //0 for word-level, 1 for char-level
    private var T9MenuArray = [String](arrayLiteral: "abc", "def", "ghi", "jkl", "mno", "pqrs", "tuv", "wxyz", "_.?")
    private var charTable = [String](arrayLiteral: "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z", "_", ".", "?")
    private var T9MenuLabel = [UILabel]()
    private var T9SubMenuCnt = [Int](arrayLiteral: 3,3,3,3,3,4,3,4,3)
    private var T9SubMenuLabel = [[UILabel]]()
    private var mainMenuPos = 4
    private var subMenuPos = 0
    private var menuLevel = 1 //1 for main menu, 2 for sub menu
    private func initT9Menu() {
        for i in 0 ..< 9 {
            let m = i / 3
            let n = i % 3
            let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 80))
            label.center = CGPoint(x: xLabel + 2*labelHeight + 40 + m * 80, y: 550 - 100*n)
            label.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2));
            label.text = T9MenuArray[i]
            label.textAlignment = NSTextAlignment.center
            label.font = UIFont(name: "Courier", size: 23.0)
            label.textColor = UIColor.white
            label.backgroundColor = UIColor.black
            label.layer.borderWidth = 1
            label.layer.borderColor = UIColor.white.cgColor
            label.isHidden = true
            T9MenuLabel.append(label)
            self.view.addSubview(label)
        }
        var cnt = 0
        for i in 0 ..< 9 {
            var subMenuLabel = [UILabel]()
            for j in 0 ..< T9SubMenuCnt[i] {
                let label = UILabel(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
                label.center = CGPoint(x: xLabel + 2*labelHeight + 80, y: 600 - 100*j)
                label.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2));
                label.text = charTable[cnt]
                cnt = cnt + 1
                label.textAlignment = NSTextAlignment.center
                label.font = UIFont(name: "Courier", size: 25.0)
                label.textColor = UIColor.white
                label.backgroundColor = UIColor.black
                label.layer.borderWidth = 1
                label.layer.borderColor = UIColor.white.cgColor
                label.isHidden = true
                subMenuLabel.append(label)
                self.view.addSubview(label)
            }
            T9SubMenuLabel.append(subMenuLabel)
        }
    }
    
    private func hideMainMenu() {
        for i in 0 ..< 9 {
            T9MenuLabel[i].isHidden = true
        }
    }
    
    private func showMainMenu() {
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor.black
        mainMenuPos = 4
        for i in 0 ..< 9 {
            T9MenuLabel[i].isHidden = false
        }
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func showSubMenu(idx: Int) {
        subMenuPos = 0
        for i in 0 ..< T9SubMenuCnt[idx] {
            T9SubMenuLabel[idx][i].isHidden = false
        }
        T9SubMenuLabel[idx][subMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func hideSubMenu(idx: Int) {
        for i in 0 ..< T9SubMenuCnt[idx] {
            T9SubMenuLabel[idx][i].isHidden = true
        }
        T9SubMenuLabel[idx][subMenuPos].backgroundColor = UIColor.black
    }
    
    private func enterSubMenu(idx: Int) {
        hideMainMenu()
        showSubMenu(idx: idx)
    }
    
    private func enterMainMenu(idx: Int) {
        hideSubMenu(idx: idx)
        showMainMenu()
    }
    
    private func charLevelMainMenuMoveLeft() {
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor.black
        mainMenuPos = (mainMenuPos - 1 + 9) % 9
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func charLevelMainMenuMoveRight() {
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor.black
        mainMenuPos = (mainMenuPos + 1) % 9
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func charLevelMainMenuMoveUp() {
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor.black
        mainMenuPos = (mainMenuPos - 3 + 9) % 9
        T9MenuLabel[mainMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func charLevelSubMenuMoveLeft() {
        T9SubMenuLabel[mainMenuPos][subMenuPos].backgroundColor = UIColor.black
        subMenuPos = (subMenuPos - 1 + T9SubMenuCnt[mainMenuPos]) % T9SubMenuCnt[mainMenuPos]
        T9SubMenuLabel[mainMenuPos][subMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func charLevelSubMenuMoveRight() {
        T9SubMenuLabel[mainMenuPos][subMenuPos].backgroundColor = UIColor.black
        subMenuPos = (subMenuPos + 1) % T9SubMenuCnt[mainMenuPos]
        T9SubMenuLabel[mainMenuPos][subMenuPos].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
    }
    
    private func hideWordMenu() {
        for i in 0 ..< 5 {
            candWordsLabel[i].isHidden = true
        }
    }
    
    private func showWordMenu() {
        for i in 0 ..< 5 {
            candWordsLabel[i].isHidden = false
        }
    }

    
    private func initView() {
        sentenceLabel = UILabel(frame: CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight))
        sentenceLabel?.center = CGPoint(x: xLabel, y: yLabel)
        sentenceLabel?.textAlignment = NSTextAlignment.left
        sentenceLabel?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2))
        sentenceLabel?.text = "The quick brown fox jumps over the lazy dog"
        sentenceLabel?.font = UIFont(name: "Courier", size: 20.0)
        sentenceLabel?.textColor = UIColor.white
        self.view.addSubview(sentenceLabel!)
        
        inputLabel = UILabel(frame: CGRect(x: 0, y: 0, width: labelWidth, height: labelHeight))
        inputLabel?.center = CGPoint(x: xLabel + labelHeight, y: yLabel)
        inputLabel?.textAlignment = NSTextAlignment.left
        inputLabel?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2))
        inputLabel?.text = ""
        inputLabel?.font = UIFont(name: "Courier", size: 20.0)
        inputLabel?.textColor = UIColor.white
        self.view.addSubview(inputLabel!)
        
        blkLabel = UILabel(frame: CGRect(x: 0, y: 0, width: labelWidth2, height: labelHeight))
        blkLabel?.center = CGPoint(x: xLabel, y: yLabel + labelOffset)
        blkLabel?.textAlignment = NSTextAlignment.left
        blkLabel?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2))
        blkLabel?.text = "BLK: 1/" + String(BLKS)
        blkLabel?.font = UIFont(name: "Courier", size: 20.0)
        blkLabel?.textColor = UIColor.white
        self.view.addSubview(blkLabel!)
        
        phrLabel = UILabel(frame: CGRect(x: 0, y: 0, width: labelWidth2, height: labelHeight))
        phrLabel?.center = CGPoint(x: xLabel + labelHeight, y: yLabel + labelOffset)
        phrLabel?.textAlignment = NSTextAlignment.left
        phrLabel?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2))
        phrLabel?.text = "PHR: 1/" + String(PHR_PER_BLK)
        phrLabel?.font = UIFont(name: "Courier", size: 20.0)
        phrLabel?.textColor = UIColor.white
        self.view.addSubview(phrLabel!)
        
        modeLabel = UILabel(frame: CGRect(x: 0, y: 0, width: labelWidth2, height: labelHeight))
        modeLabel?.center = CGPoint(x: xLabel + 2*labelHeight, y: yLabel + labelOffset)
        modeLabel?.textAlignment = NSTextAlignment.left
        modeLabel?.transform = CGAffineTransform(rotationAngle: CGFloat(Double.pi * 3/2))
        modeLabel?.text = "Mode: Char"
        modeLabel?.font = UIFont(name: "Courier", size: 20.0)
        modeLabel?.textColor = UIColor.white
        self.view.addSubview(modeLabel!)
        
//         self.addKeyboardPic()
        self.initWordsLabel()
        self.initT9Menu()
        if(inputMode == 1) {
            hideWordMenu()
            showMainMenu()
        }
    }
    
    //add keyboard pictures in the screen
    private func addKeyboardPic() {
        let keyboardPic = UIImage(named: "keyboard")
        let keyboardView = UIImageView(image: keyboardPic)
        keyboardView.transform = CGAffineTransform(rotationAngle: CGFloat.pi*3/2)
        keyboardView.frame = CGRect(x: 180, y: 150, width: 200, height: 600)
        self.view.addSubview(keyboardView)
    }
    
    private func loadSentences() {
        var offset: Int = 0
        var tempArr = [String]()
        if let path = Bundle.main.path(forResource: "phrases", ofType: "txt") { //change in word
            do {
                let data = try String(contentsOfFile: path, encoding: .utf8)
                let sentence = data.components(separatedBy: "\r\n")
                tempArr.append(contentsOf: sentence)
            } catch {
                print(error)
            }
        }
        //drop the last zero-len one and shuffle the sentences
        let _ = tempArr.popLast()
        tempArr.shuffle()
        print(tempArr)
       
        var data: String = ""
        for i in 0..<BLKS*PHR_PER_BLK {
            var tempSent = ""
//            if((i % PHR_PER_BLK) - PHR_PER_BLK + 2 == 0) {
//                tempSent = "the quick brown fox jumps over the lazy dog "
//            } else if((i % PHR_PER_BLK) - PHR_PER_BLK + 2 == 1) {
//                tempSent = "the five boxing wizards jump quickly "
//            } else {
                tempSent = tempArr[offset]
                offset += 1;
//            }
            sentenceArray.append(tempSent)
            data = data + tempSent + "\n"
        }
        
        //write sentences to files
        if let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let filename = path.appendingPathComponent("sentences.txt")
            do {
                try data.write(to: filename, atomically: false, encoding: .utf8)
            } catch {
                print("Write senteces to files failed")
            }
        }
        
        setSentence()
    }
    
    private var allData:String = ""
    private var sentenceData:String = ""
    private var curSentence:Int = 0
    private var curChar:Int = 0 //current char in current sentence
    private var isRest:Bool = false
    
    private func setSentence() {
        if curSentence >= sentenceArray.count {
            DispatchQueue.main.async {
                self.sentenceLabel?.text = "Finished!"
                self.isRest = true
            }
            if let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
                let filename = path.appendingPathComponent("alldata.txt")
                    do {
                        try allData.write(to: filename, atomically: true, encoding: .utf8)
                    } catch {
                        print("Write data to files failed")
                }
            }
            return;
        }
        DispatchQueue.main.async {
            self.sentenceLabel?.text = self.sentenceArray[self.curSentence] + " "//change in word
            self.blkLabel?.text = "BLK: " + String(self.curSentence/PHR_PER_BLK+1) + "/" + String(BLKS)
            self.phrLabel?.text = "PHR: " + String(self.curSentence%PHR_PER_BLK+1) + "/" + String(PHR_PER_BLK)
        }
        curWords = sentenceArray[curSentence].components(separatedBy: " ")
        curPointer = 0
    }
    
    private func nextSentence() {
        if(inputLabel!.text?.count != sentenceLabel!.text?.count) {
            return;
        }
        mainMenuPos = 4
        subMenuPos = 0
        if let path = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            sentenceData += "\n" + String(matchY) + " " + String(matchN) + " " + String(selectY) + " " + String(selectN) + " " + String(undo) + " " + String(del) + "\n"
            sentenceData += (inputLabel?.text!)! + "\n"
            let result = sentenceData
            allData += sentenceData
            sentenceData = ""
            print(result)
            let filename = path.appendingPathComponent(String(curSentence) + ".txt")
            do {
                try result.write(to: filename, atomically: true, encoding: .utf8)
            } catch {
                print("Write data to files failed")
            }
        }
        
        curSentence = curSentence + 1
        curChar = 0
        clearAll()
        setSentence()
    }
    
    private func clearAll() { //when switch to next sentence, clear everything
        for i in 0..<5 {
            candWordsLabel[i].text = ""
            candWordsLabel[i].backgroundColor = UIColor.black
        }
        curPointer = 0
        inputLabel!.text = ""
        curCandNum = 0
        matchY = 0; matchN = 0; selectY = 0; selectN = 0; undo = 0; del = 0
        sentenceData = ""
    }
    
    private func clearInput() {
        if(candWordsLabel[0].text!.count > 0) {
            undo += 1
            for i in 0..<5 {
                candWordsLabel[i].text = ""
                candWordsLabel[i].backgroundColor = UIColor.black
            }
        } else { //clear word by word
            if(curPointer != 0) {
                del += 1
                curPointer = curPointer - 1
                let str = inputLabel!.text!
                let start = str.index(str.startIndex, offsetBy: 0)
                let end = str.index(str.endIndex, offsetBy: -curWords[curPointer].count-1)
                let range = start..<end
                inputLabel!.text! = String(str[range])
                //modify input label
            }
        }
        curCandNum = 0
        sentenceData = ""
        curChar = 0
    }
    
    private func appendInput() {
        inputLabel!.text = inputLabel!.text! + "*"
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        let touchPoint = (touches as NSSet).allObjects[0] as! UITouch
        let coord = touchPoint.location(in: self.jetView)
        let viewContent = self.jetView.bounds
        let xRatio = Float(coord.x / viewContent.size.width)
        let yRatio = Float(coord.y / viewContent.size.height)
        print(coord.x, coord.y)
        print(xRatio, yRatio)
//        let realZ = getDepth(from: depthPixelBuffer!, atXRatio: xRatio, atYRatio: yRatio)
////        print(refWidth!, refHeight!)
//        let realX = (xRatio * refWidth! - camOx!) * realZ / camFx!
//        let realY = (yRatio * refHeight! - camOy!) * realZ / camFy!
//        DispatchQueue.main.async {
//            self.touchCoord.text = String.localizedStringWithFormat("X = %.2f cm, Y = %.2f cm, Z = %.2f cm", realX, realY, realZ)
//        }
    }
    
    // MARK: - View Controller Life Cycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        initView()
        loadSentences()
        OpenCVWrapper.loadData() //load centroids data
        
        // Keep the screen unlock
        UIApplication.shared.isIdleTimerDisabled = true
        if(cntFrames) {
            let timer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.fire), userInfo: nil, repeats: true)
        }
        
        viewFrameSize = self.view.frame.size
        
        // test cv
        print("\(OpenCVWrapper.openCVVersionString())")
        
        // Show the jetView rather than cloud view
//        self.cloudView.isHidden = JETEnabled
        self.jetView.isHidden = !JETEnabled
        
        // 平滑的接口
        // self.depthDataOutput.isFilteringEnabled = smoothChoice
        
        
        
        // Check video authorization status, video access is required
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            // The user has previously granted access to the camera
            break
            
        case .notDetermined:
            /*
             The user has not yet been presented with the option to grant video access
             We suspend the session queue to delay session setup until the access request has completed
             */
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })
            
        default:
            // The user has previously denied access
            setupResult = .notAuthorized
        }
        
        /*
         Setup the capture session.
         In general it is not safe to mutate an AVCaptureSession or any of its
         inputs, outputs, or connections from multiple threads at the same time.
         
         Why not do all of this on the main queue?
         Because AVCaptureSession.startRunning() is a blocking call which can
         take a long time. We dispatch session setup to the sessionQueue so
         that the main queue isn't blocked, which keeps the UI responsive.
         */
        sessionQueue.async {
            self.configureSession()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let interfaceOrientation = UIApplication.shared.statusBarOrientation
        statusBarOrientation = interfaceOrientation
        
        let initialThermalState = ProcessInfo.processInfo.thermalState
        if initialThermalState == .serious || initialThermalState == .critical {
            showThermalState(state: initialThermalState)
        }
        
        sessionQueue.async {
            switch self.setupResult {
            case .success:
                // Only setup observers and start the session running if setup succeeded
                self.addObservers()
                let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                let videoDevicePosition = self.videoDeviceInput.device.position
                let rotation = PreviewMetalView.Rotation(with: interfaceOrientation,
                                                         videoOrientation: videoOrientation,
                                                         cameraPosition: videoDevicePosition)
                self.jetView.mirroring = (videoDevicePosition == .front)
                if let rotation = rotation {
                    self.jetView.rotation = rotation
                }
                self.dataOutputQueue.async {
                    self.renderingEnabled = true
                }
                
                
                
                self.session.startRunning()
                self.isSessionRunning = self.session.isRunning
                
            case .notAuthorized:
                DispatchQueue.main.async {
                    let message = NSLocalizedString("TrueDepthStreamer doesn't have permission to use the camera, please change privacy settings",
                                                    comment: "Alert message when the user has denied access to the camera")
                    let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"),
                                                            style: .cancel,
                                                            handler: nil))
                    alertController.addAction(UIAlertAction(title: NSLocalizedString("Settings", comment: "Alert button to open Settings"),
                                                            style: .`default`,
                                                            handler: { _ in
                                                                UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!,
                                                                                          options: [:],
                                                                                          completionHandler: nil)
                    }))
                    
                    self.present(alertController, animated: true, completion: nil)
                }
                
            case .configurationFailed:
                DispatchQueue.main.async {
                    self.cameraUnavailableLabel.isHidden = false
                    self.cameraUnavailableLabel.alpha = 0.0
                    UIView.animate(withDuration: 0.25) {
                        self.cameraUnavailableLabel.alpha = 1.0
                    }
                }
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        dataOutputQueue.async {
            self.renderingEnabled = false
        }
        sessionQueue.async {
            if self.setupResult == .success {
                self.session.stopRunning()
                self.isSessionRunning = self.session.isRunning
            }
        }
        
        super.viewWillDisappear(animated)
    }
    
    @objc
    func didEnterBackground(notification: NSNotification) {
        // Free up resources
        dataOutputQueue.async {
            self.renderingEnabled = false
            //            if let videoFilter = self.videoFilter {
            //                videoFilter.reset()
            //            }
            self.videoDepthMixer.reset()
            self.videoDepthConverter.reset()
            self.jetView.pixelBuffer = nil
            self.jetView.flushTextureCache()
        }
    }
    
    @objc
    func willEnterForground(notification: NSNotification) {
        dataOutputQueue.async {
            self.renderingEnabled = true
        }
    }
    
    // You can use this opportunity to take corrective action to help cool the system down.
    @objc
    func thermalStateChanged(notification: NSNotification) {
        if let processInfo = notification.object as? ProcessInfo {
            showThermalState(state: processInfo.thermalState)
        }
    }
    
    func showThermalState(state: ProcessInfo.ThermalState) {
        DispatchQueue.main.async {
            var thermalStateString = "UNKNOWN"
            if state == .nominal {
                thermalStateString = "NOMINAL"
            } else if state == .fair {
                thermalStateString = "FAIR"
            } else if state == .serious {
                thermalStateString = "SERIOUS"
            } else if state == .critical {
                thermalStateString = "CRITICAL"
            }
            
            let message = NSLocalizedString("Thermal state: \(thermalStateString)", comment: "Alert message when thermal state has changed")
            let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
            alertController.addAction(UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil))
            self.present(alertController, animated: true, completion: nil)
        }
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .all
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        coordinator.animate(
            alongsideTransition: { _ in
                let interfaceOrientation = UIApplication.shared.statusBarOrientation
                self.statusBarOrientation = interfaceOrientation
                self.sessionQueue.async {
                    /*
                     The photo orientation is based on the interface orientation. You could also set the orientation of the photo connection based
                     on the device orientation by observing UIDeviceOrientationDidChangeNotification.
                     */
                    let videoOrientation = self.videoDataOutput.connection(with: .video)!.videoOrientation
                    if let rotation = PreviewMetalView.Rotation(with: interfaceOrientation, videoOrientation: videoOrientation,
                                                                cameraPosition: self.videoDeviceInput.device.position) {
                        self.jetView.rotation = rotation
                    }
                }
        }, completion: nil
        )
    }
    
    // MARK: - KVO and Notifications
    
    private var sessionRunningContext = 0
    
    private func addObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(didEnterBackground),
                                               name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(willEnterForground),
                                               name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(thermalStateChanged),
                                               name: ProcessInfo.thermalStateDidChangeNotification,	object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionRuntimeError),
                                               name: NSNotification.Name.AVCaptureSessionRuntimeError, object: session)
        
        
        session.addObserver(self, forKeyPath: "running", options: NSKeyValueObservingOptions.new, context: &sessionRunningContext)
        
        /*
         A session can only run when the app is full screen. It will be interrupted
         in a multi-app layout, introduced in iOS 9, see also the documentation of
         AVCaptureSessionInterruptionReason. Add observers to handle these session
         interruptions and show a preview is paused message. See the documentation
         of AVCaptureSessionWasInterruptedNotification for other interruption reasons.
         */
        NotificationCenter.default.addObserver(self, selector: #selector(sessionWasInterrupted),
                                               name: NSNotification.Name.AVCaptureSessionWasInterrupted,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(sessionInterruptionEnded),
                                               name: NSNotification.Name.AVCaptureSessionInterruptionEnded,
                                               object: session)
        NotificationCenter.default.addObserver(self, selector: #selector(subjectAreaDidChange),
                                               name: NSNotification.Name.AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        session.removeObserver(self, forKeyPath: "running", context: &sessionRunningContext)

    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context != &sessionRunningContext {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    
    // MARK: - Session Management
    
    // Call this on the session queue
    private func configureSession() {
        if setupResult != .success {
            return
        }
        
        let defaultVideoDevice: AVCaptureDevice? = videoDeviceDiscoverySession.devices.first
        
        guard let videoDevice = defaultVideoDevice else {
            print("Could not find any video device")
            setupResult = .configurationFailed
            return
        }
        
        do {
            videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
        } catch {
            print("Could not create video device input: \(error)")
            setupResult = .configurationFailed
            return
        }
        
        session.beginConfiguration()
        
        // Set up audio device
        guard let audioDevice = AVCaptureDevice.default(.builtInMicrophone, for: AVMediaType.audio, position: .unspecified) else {
            return
        }
        do {
            let audioInput = try AVCaptureDeviceInput(device: audioDevice)
            if session.canAddInput(audioInput) {
                session.addInput(audioInput)
            } else {
                print("Could not add audio input")
            }
        } catch {
            print("Could not get audio device input: \(error)")
        }
        if session.canAddOutput(audioDataOutput) {
            session.addOutput(audioDataOutput)
        }
        audioDataOutput.setSampleBufferDelegate(self, queue: audioQueue)
        
        session.sessionPreset = AVCaptureSession.Preset.vga640x480
        
        // Add a video input
        guard session.canAddInput(videoDeviceInput) else {
            print("Could not add video device input to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        session.addInput(videoDeviceInput)
//        captureSession.addInput(videoDeviceInput)
        
        // Add a video data output
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        } else {
            print("Could not add video data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Add a depth data output
        if session.canAddOutput(depthDataOutput) {
            session.addOutput(depthDataOutput)
            depthDataOutput.isFilteringEnabled = smoothChoice
            if let connection = depthDataOutput.connection(with: .depthData) {
                connection.isEnabled = true
            } else {
                print("No AVCaptureConnection")
            }
        } else {
            print("Could not add depth data output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Search for highest resolution with half-point depth values
        let depthFormats = videoDevice.activeFormat.supportedDepthDataFormats
        let filtered = depthFormats.filter({
            CMFormatDescriptionGetMediaSubType($0.formatDescription) == kCVPixelFormatType_DepthFloat16
        })
        let selectedFormat = filtered.max(by: {
            first, second in CMVideoFormatDescriptionGetDimensions(first.formatDescription).width < CMVideoFormatDescriptionGetDimensions(second.formatDescription).width
        })
        
        do {
            try videoDevice.lockForConfiguration()
            videoDevice.activeDepthDataFormat = selectedFormat
            videoDevice.unlockForConfiguration()
        } catch {
            print("Could not lock device for configuration: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }
        
        // Use an AVCaptureDataOutputSynchronizer to synchronize the video data and depth data outputs.
        // The first output in the dataOutputs array, in this case the AVCaptureVideoDataOutput, is the "master" output.
        outputSynchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoDataOutput, depthDataOutput])
        outputSynchronizer!.setDelegate(self, queue: dataOutputQueue)
        session.commitConfiguration()
        
//        captureSession.addOutput(self.fileOutput)
//        captureSession.startRunning()
    }
    
    private func focus(with focusMode: AVCaptureDevice.FocusMode,
                       exposureMode: AVCaptureDevice.ExposureMode,
                       at devicePoint: CGPoint,
                       monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            let videoDevice = self.videoDeviceInput.device
            
            do {
                try videoDevice.lockForConfiguration()
                if videoDevice.isFocusPointOfInterestSupported && videoDevice.isFocusModeSupported(focusMode) {
                    videoDevice.focusPointOfInterest = devicePoint
                    videoDevice.focusMode = focusMode
                }
                
                if videoDevice.isExposurePointOfInterestSupported && videoDevice.isExposureModeSupported(exposureMode) {
                    videoDevice.exposurePointOfInterest = devicePoint
                    videoDevice.exposureMode = exposureMode
                }
                
                videoDevice.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                videoDevice.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }
    
//    @IBAction private func changeMixFactor(_ sender: UISlider) {
//        let mixFactor = sender.value
//
//        dataOutputQueue.async {
//            self.videoDepthMixer.mixFactor = mixFactor
//        }
//    }

    
    @objc
    func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }
    
    @objc
    func sessionWasInterrupted(notification: NSNotification) {
        // In iOS 9 and later, the userInfo dictionary contains information on why the session was interrupted.
        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")
            
            if reason == .videoDeviceInUseByAnotherClient {
                // Simply fade-in a button to enable the user to try to resume the session running.
                resumeButton.isHidden = false
                resumeButton.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.resumeButton.alpha = 1.0
                }
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                // Simply fade-in a label to inform the user that the camera is unavailable.
                cameraUnavailableLabel.isHidden = false
                cameraUnavailableLabel.alpha = 0.0
                UIView.animate(withDuration: 0.25) {
                    self.cameraUnavailableLabel.alpha = 1.0
                }
            }
        }
    }
    
    @objc
    func sessionInterruptionEnded(notification: NSNotification) {
        if !resumeButton.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.resumeButton.alpha = 0
            }, completion: { _ in
                self.resumeButton.isHidden = true
            }
            )
        }
        if !cameraUnavailableLabel.isHidden {
            UIView.animate(withDuration: 0.25,
                           animations: {
                            self.cameraUnavailableLabel.alpha = 0
            }, completion: { _ in
                self.cameraUnavailableLabel.isHidden = true
            }
            )
        }
    }
    
    @objc
    func sessionRuntimeError(notification: NSNotification) {
        guard let errorValue = notification.userInfo?[AVCaptureSessionErrorKey] as? NSError else {
            return
        }
        
        let error = AVError(_nsError: errorValue)
        print("Capture session runtime error: \(error)")
        
        /*
         Automatically try to restart the session running if media services were
         reset and the last start running succeeded. Otherwise, enable the user
         to try to resume the session running.
         */
        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                } else {
                    DispatchQueue.main.async {
                        self.resumeButton.isHidden = false
                    }
                }
            }
        } else {
            resumeButton.isHidden = false
        }
    }
    
    @IBAction private func resumeInterruptedSession(_ sender: UIButton) {
        sessionQueue.async {
            /*
             The session might fail to start running. A failure to start the session running will be communicated via
             a session runtime error notification. To avoid repeatedly failing to start the session
             running, we only try to restart the session running in the session runtime error handler
             if we aren't trying to resume the session running.
             */
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    let message = NSLocalizedString("Unable to resume", comment: "Alert message when unable to resume the session running")
                    let alertController = UIAlertController(title: "TrueDepthStreamer", message: message, preferredStyle: .alert)
                    let cancelAction = UIAlertAction(title: NSLocalizedString("OK", comment: "Alert OK button"), style: .cancel, handler: nil)
                    alertController.addAction(cancelAction)
                    self.present(alertController, animated: true, completion: nil)
                }
            } else {
                DispatchQueue.main.async {
                    self.resumeButton.isHidden = true
                }
            }
        }
    }
    
    // MARK: - Point cloud view gestures
    
    @IBAction private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.numberOfTouches != 2 {
            return
        }
        if gesture.state == .began {
            lastScale = 1
        } else if gesture.state == .changed {
            let scale = Float(gesture.scale)
            let diff: Float = scale - lastScale
            let factor: Float = 1e3
            if scale < lastScale {
                lastZoom = diff * factor
            } else {
                lastZoom = diff * factor
            }
            DispatchQueue.main.async {
                // self.autoPanningSwitch.isOn = false
                // self.autoPanningIndex = -1
            }
            cloudView.moveTowardCenter(lastZoom)
            lastScale = scale
        } else if gesture.state == .ended {
        } else {
        }
    }
    
//    @IBAction private func handlePanOneFinger(gesture: UIPanGestureRecognizer) {
//        if gesture.numberOfTouches != 1 {
//            return
//        }
//
//        if gesture.state == .began {
//            let pnt: CGPoint = gesture.translation(in: cloudView)
//            lastXY = pnt
//        } else if (.failed != gesture.state) && (.cancelled != gesture.state) {
//            let pnt: CGPoint = gesture.translation(in: cloudView)
//            DispatchQueue.main.async {
//                self.autoPanningSwitch.isOn = false
//                self.autoPanningIndex = -1
//            }
//            cloudView.yawAroundCenter(Float((pnt.x - lastXY.x) * 0.1))
//            cloudView.pitchAroundCenter(Float((pnt.y - lastXY.y) * 0.1))
//            lastXY = pnt
//        }
//    }
//
//    @IBAction private func handleDoubleTap(gesture: UITapGestureRecognizer) {
//        DispatchQueue.main.async {
//            self.autoPanningSwitch.isOn = false
//            self.autoPanningIndex = -1
//        }
//        cloudView.resetView()
//    }
    
//    @IBAction private func handleRotate(gesture: UIRotationGestureRecognizer) {
//        if gesture.numberOfTouches != 2 {
//            return
//        }
//
//        if gesture.state == .changed {
//            let rot = Float(gesture.rotation)
//            DispatchQueue.main.async {
//                self.autoPanningSwitch.isOn = false
//                self.autoPanningIndex = -1
//            }
//            cloudView.rollAroundCenter(rot * 60)
//            gesture.rotation = 0
//        }
//    }
    
    // MARK: - JET view Depth label gesture
    
    @IBAction private func handleLongPressJET(gesture: UILongPressGestureRecognizer) {
        
        switch gesture.state {
        case .began:
            touchDetected = true
            let pnt: CGPoint = gesture.location(in: self.jetView)
            touchCoordinates = pnt
        case .changed:
            let pnt: CGPoint = gesture.location(in: self.jetView)
            touchCoordinates = pnt
        case .possible, .ended, .cancelled, .failed:
            touchDetected = false
            DispatchQueue.main.async {
                self.touchDepth.text = ""
            }
        }
    }
        
    private func saveCurrentScreen() -> UIImage {
        let context = CIContext()
        let texture = self.jetView.currentDrawable!.texture
        let cImg = CIImage(mtlTexture: texture, options: nil)!
        let cgImg = context.createCGImage(cImg, from: cImg.extent)!
        let image = UIImage(cgImage: cgImg)
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
        return image
    }
        
    @objc func image(_ image: UIImage, didFinishSavingWithError error: NSError?, contextInfo:UnsafeRawPointer) {
        if let e = error as NSError? {
            print(e)
        } else {
            UIAlertController.init(title: nil,
                                   message: "Save Success",
                                   preferredStyle: UIAlertController.Style.alert).show(self, sender: nil);
        }
    }
        
    private var packets: Int = 0
    private let flagQueue = DispatchQueue(label: "flagQueue")
    private var flag: Int = 4
    private var lastTouchTS: Int64 = 0
    private var touched: Bool = false
    private let minTouchInterval: Int = 50
    private let minCnt: Int = 80
    private let delayFrame: Int = 3
    
    func captureOutput(_ captureOutput: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        var blockBuffer: CMBlockBuffer?
        var audioBufferList = AudioBufferList()
        var cnt = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: &audioBufferList, bufferListSize: MemoryLayout<AudioBufferList>.size, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment, blockBufferOut: &blockBuffer)
        let buffers = UnsafeBufferPointer<AudioBuffer>(start: &audioBufferList.mBuffers, count: Int(audioBufferList.mNumberBuffers))
        // mNumberBuffers normally equals to 1
        for audioBuffer in buffers {
            let buffer = audioBuffer.mData?.assumingMemoryBound(to: Int8.self) //Int8 or UInt8 ??
            let numFrames = audioBuffer.mDataByteSize / 2
            for i in 0..<numFrames {
                let d = Int32((buffer?[Int(2*i+1)])!) << 8 + Int32((buffer?[Int(2*i)])!)
                if(d > 3000 || d < -3000) {
                    cnt = cnt + 1
                }
            }
            
            if(cnt > 0) {
                let curTS: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
//                print(cnt, curTS)
                if(cnt > minCnt && curTS - lastTouchTS > minTouchInterval) {
                    serialQueue.sync { touched = true }
//                    print("trigger", curTS)
                    lastTouchTS = curTS
                }
            }
        }
    }
    
    func convertCIImageToCGImage(inputImage: CIImage) -> CGImage? {
        let context = CIContext(options: nil)
        if let cgImage = context.createCGImage(inputImage, from: inputImage.extent) {
            return cgImage
        }
        return nil
    }
    
    // MARK: - Video + Depth Frame Processing
    func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        if isRest {
            return
        }
        if(cntFrames) {
            serialQueue.sync {
                fps += 1
            }
        }
        
        if !renderingEnabled {
            return
        }
        
        // Read all outputs
        guard renderingEnabled,
            let syncedDepthData: AVCaptureSynchronizedDepthData =
            synchronizedDataCollection.synchronizedData(for: depthDataOutput) as? AVCaptureSynchronizedDepthData,
            let syncedVideoData: AVCaptureSynchronizedSampleBufferData =
            synchronizedDataCollection.synchronizedData(for: videoDataOutput) as? AVCaptureSynchronizedSampleBufferData else {
                // only work on synced pairs
                return
        }
        
        if syncedDepthData.depthDataWasDropped || syncedVideoData.sampleBufferWasDropped {
            return
        }
        

        
        let depthData = syncedDepthData.depthData
        let depthPixelBuffer = depthData.depthDataMap
//        print(CVPixelBufferGetWidth(depthPixelBuffer))
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let videoPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
            let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                return
        }
        
        if JETEnabled {
            if !videoDepthConverter.isPrepared {
                /*
                 outputRetainedBufferCountHint is the number of pixel buffers we expect to hold on to from the renderer.
                 This value informs the renderer how to size its buffer pool and how many pixel buffers to preallocate. Allow 2 frames of latency
                 to cover the dispatch_async call.
                 */
                var depthFormatDescription: CMFormatDescription?
                CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault,
                                                             imageBuffer: depthPixelBuffer,
                                                             formatDescriptionOut: &depthFormatDescription)
                videoDepthConverter.prepare(with: depthFormatDescription!, outputRetainedBufferCountHint: 2)
            }
            
            if !videoDepthMixer.isPrepared {
                videoDepthMixer.prepare(with: formatDescription, outputRetainedBufferCountHint: 3)
            }
            
//            guard let result = videoDepthConverter.render(pixelBuffer: depthPixelBuffer, imgBuffer: videoPixelBuffer) else {
//                print("Unable to process depth")
//                return
//            }
            
            
            // Mix the video buffer with the last depth data we received
//            guard let mixedBuffer = videoDepthMixer.mix(videoPixelBuffer: videoPixelBuffer, depthPixelBuffer: jetPixelBuffer) else {
//                print("Unable to combine video and depth")
//                return
//            }
//
//            jetView.pixelBuffer = mixedBuffer

            
            if(flag <= delayFrame) {
                flag = flag + 1
            }
            let pressed = (flag == delayFrame) ? true : false;
            if pressed {
//                print("pressed")
            }
            
            var curLength:Int
            if(curPointer == curWords.count) {
                curLength = -1
            } else {
                curLength = curWords[curPointer].count
            }
            
            guard let result = videoDepthConverter.render(pixelBuffer: depthPixelBuffer, imgBuffer: videoPixelBuffer, press: pressed, curLength: curLength) else {
                print("Unable to process depth")
                return
            }
            if(flag == delayFrame) { //save picture when a tap happens
//                print("save")
//                DispatchQueue.main.async {
//                    let ciImage = CIImage(cvPixelBuffer: result.jetBuffer)
//                    let image = UIImage(cgImage: self.convertCIImageToCGImage(inputImage: ciImage)!)
//                    UIImageWriteToSavedPhotosAlbum(image, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
//                }
            }
            if touched {
                serialQueue.sync { touched = false }
                flag = 0
            }
            
            let dict = result.dict
            if(inputMode == 0) {
                handleWordLevel(dict: dict)
            } else {
                handleCharLevel(dict: dict)
            }
            jetView.pixelBuffer = result.jetBuffer
        }
    }
    
    //variables for char level input
    private var charOp:Int = 0
    private func handleCharLevel(dict: NSDictionary) {
        let moveLeft = dict["moveLeft"] as! Bool
        let moveRight = dict["moveRight"] as! Bool
        let moveUp = dict["moveUp"] as! Bool
        let validTouch = dict["validTouch"] as! Bool
        let touchHand = dict["touchHand"] as! Int
        if(moveLeft) {
            charOp += 1
            if(menuLevel == 1) {
                DispatchQueue.main.async {
                    self.charLevelMainMenuMoveLeft()
                }
            } else if(menuLevel == 2) {
                DispatchQueue.main.async {
                    self.charLevelSubMenuMoveLeft()
                }
            }
        }
        if(moveRight) {
            charOp += 1
            if(menuLevel == 1) {
                DispatchQueue.main.async {
                    self.charLevelMainMenuMoveRight()
                }
            } else if(menuLevel == 2) {
                DispatchQueue.main.async {
                    self.charLevelSubMenuMoveRight()
                }
            }
        }
        if(moveUp) {
            charOp += 1
            if(menuLevel == 1) {
                DispatchQueue.main.async {
                    self.charLevelMainMenuMoveUp()
                }
            }
        }
        if(validTouch) {
            DispatchQueue.main.sync {
                if(self.inputLabel!.text?.count == 0 || self.inputLabel!.text?.count == self.sentenceLabel!.text?.count) {
                    sentenceData += String(Date().timeIntervalSince1970) + " "
                    print(Date().timeIntervalSince1970)
                }
                if(self.inputLabel!.text?.count == self.sentenceLabel!.text?.count) {
                    sentenceData += String(charOp) + " "
                    print(charOp)
                    charOp = 0
                    self.nextSentence()
                    return
                }
                if(touchHand == 0) { //touch with left hand
                    if(menuLevel == 2) { //return to main menu
                        DispatchQueue.main.async {
                            if(self.inputLabel!.text?.count != self.sentenceLabel!.text?.count) {
                                self.enterMainMenu(idx: self.mainMenuPos)
                                self.menuLevel = 1
                            }
                        }
                    } else if(menuLevel == 1) { //erase one character
                        DispatchQueue.main.async {
                            let str = self.inputLabel!.text!
                            if(str.count > 0) {
                                let start = str.index(str.startIndex, offsetBy: 0)
                                let end = str.index(str.endIndex, offsetBy: -1)
                                let range = start..<end
                                self.inputLabel!.text! = String(str[range])
                            }
                        }
                    }
                } else { //touch with right hand
                    if(menuLevel == 2) { //select this character and return to main menu
                        DispatchQueue.main.async {
                            if(self.T9SubMenuLabel[self.mainMenuPos][self.subMenuPos].text! == "_") {
                                self.inputLabel?.text! += "_"
                            } else {
                                self.inputLabel?.text! += self.T9SubMenuLabel[self.mainMenuPos][self.subMenuPos].text!
                            }
                            self.enterMainMenu(idx: self.mainMenuPos)
                            self.menuLevel = 1
                        }
                    } else if(menuLevel == 1) {
                        DispatchQueue.main.async { //enter sub menu
                            self.enterSubMenu(idx: self.mainMenuPos)
                            self.menuLevel = 2
                        }
                    }
                }
            }
        }
    }
    
    private func handleWordLevel(dict: NSDictionary) {
        let moveLeft = dict["moveLeft"] as! Bool
        let moveRight = dict["moveRight"] as! Bool
        let validTouch = dict["validTouch"] as! Bool
        let thumbTouch = dict["thumb"] as! Bool
        if(moveLeft) {
            DispatchQueue.main.async {
                self.clearInput()
            }
        }
        if(moveRight) {
            DispatchQueue.main.async {
                if(self.candWordsLabel[0].text!.count > 0) {
                    self.candWordsLabel[self.curCandNum].backgroundColor = UIColor.black
                    self.curCandNum = (self.curCandNum + 1) % candNum
                    self.candWordsLabel[self.curCandNum].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
                }
            }
        }
        
        if(validTouch) {
            if(thumbTouch) { //touch with thumb means select this word or jump to next
                DispatchQueue.main.async {
                    if(self.inputLabel!.text?.count == self.sentenceLabel!.text?.count) {
                        self.nextSentence()
                    } else { //select words
                        if(self.candWordsLabel[self.curCandNum].text! == self.curWords[self.curPointer]) {
                            if(self.curCandNum == 0) {
                                self.matchY += 1
                            } else {
                                self.selectY += 1
                            }
                        } else {
                            if(self.curCandNum == 0) {
                                self.matchN += 1
                            } else {
                                self.selectN += 1
                            }
                        }
                        self.curPointer += 1
                        self.inputLabel?.text! += self.candWordsLabel[self.curCandNum].text! + " "
                        for i in 0..<5 {
                            self.candWordsLabel[i].text = ""
                            self.candWordsLabel[i].backgroundColor = UIColor.black
                        }
                        self.curCandNum = 0
                    }
                }
            } else {
                DispatchQueue.main.async {
                    let words:NSArray = dict["words"] as! NSMutableArray
                    var wordArr = Array<String>()
                    var exist:Bool = false
                    for i in 0..<candNum {
                        let word = words[i] as! String
                        wordArr.append(word)
                        if(word == self.curWords[self.curPointer]) {
                            exist = true
                        }
                    }
                    for i in 0..<candNum {
                        self.candWordsLabel[i].text = wordArr[i]
                        if(wordArr[i].count >= 10) {
                            self.candWordsLabel[i].font = UIFont(name: "Courier", size: 18.0)
                        } else {
                            self.candWordsLabel[i].font = UIFont(name: "Courier", size: 20.0)
                        }
                    }
                    self.candWordsLabel[self.curCandNum].backgroundColor = UIColor(red: 0/255, green: 125/255, blue: 0/255, alpha: 1.0)
                }
//                let touchX = dict["touchX"] as! Float
//                let touchY = dict["touchY"] as! Float
//                let touchZ = dict["touchZ"] as! Float
//                let xcoord = dict["xcoord"] as! Int
//                let ycoord = dict["ycoord"] as! Int
                sentenceData += String(Date().timeIntervalSince1970) + " "
            }
        }
    }
}

extension AVCaptureVideoOrientation {
    init?(interfaceOrientation: UIInterfaceOrientation) {
        switch interfaceOrientation {
        case .portrait: self = .portrait
        case .portraitUpsideDown: self = .portraitUpsideDown
        case .landscapeLeft: self = .landscapeLeft
        case .landscapeRight: self = .landscapeRight
        default: return nil
        }
    }
}

extension PreviewMetalView.Rotation {
    
    init?(with interfaceOrientation: UIInterfaceOrientation, videoOrientation: AVCaptureVideoOrientation, cameraPosition: AVCaptureDevice.Position) {
        /*
         Calculate the rotation between the videoOrientation and the interfaceOrientation.
         The direction of the rotation depends upon the camera position.
         */
        switch videoOrientation {
            
        case .portrait:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portrait:
                self = .rotate0Degrees
                
            case .portraitUpsideDown:
                self = .rotate180Degrees
                
            default: return nil
            }
            
        case .portraitUpsideDown:
            switch interfaceOrientation {
            case .landscapeRight:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .landscapeLeft:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portrait:
                self = .rotate180Degrees
                
            case .portraitUpsideDown:
                self = .rotate0Degrees
                
            default: return nil
            }
            
        case .landscapeRight:
            switch interfaceOrientation {
            case .landscapeRight:
                self = .rotate0Degrees
                
            case .landscapeLeft:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            default: return nil
            }
            
        case .landscapeLeft:
            switch interfaceOrientation {
            case .landscapeLeft:
                self = .rotate0Degrees
                
            case .landscapeRight:
                self = .rotate180Degrees
                
            case .portrait:
                self = cameraPosition == .front ? .rotate90Degrees : .rotate270Degrees
                
            case .portraitUpsideDown:
                self = cameraPosition == .front ? .rotate270Degrees : .rotate90Degrees
                
            default: return nil
            }
        }
    }
}
