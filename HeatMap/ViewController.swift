//
//  ViewController.swift
//  HeatMap
//
//  Created by Igor Fereira on 27/11/2018.
//  Copyright © 2018 AndrewZimmer. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    weak var eyeTracker: EyeTracker? = nil
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    

    @IBAction func startTracker(_ sender: UIControl) {
        
        guard let presentation = UIApplication.shared.delegate?.window, presentation != nil else {
            return
        }
        
        let window = presentation!
        
        if let tracker = self.eyeTracker {
            tracker.restore(window)
        }
        
        self.eyeTracker = EyeTrackingViewController.buildTracker(tracking: window)
    }
    
    @IBAction func stopTracker(_ sender: UIControl) {
        
        guard let presentation = UIApplication.shared.delegate?.window, presentation != nil else {
            return
        }
        
        let window = presentation!
        
        if let tracker = self.eyeTracker {
            tracker.restore(window)
        }
        
        self.eyeTracker = nil
    }

}
