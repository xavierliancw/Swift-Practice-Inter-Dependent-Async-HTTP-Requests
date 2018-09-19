//
//  ViewController.swift
//  Practice Inter-Dependent Async HTTP Requests
//
//  Created by Xavier Lian on 9/19/18.
//  Copyright © 2018 Xavier Lian. All rights reserved.
//

import UIKit

class ViewController: UIViewController
{
    let svc = SVCAsync()
    
    var conTop: NSLayoutConstraint!
    var conBot: NSLayoutConstraint!
    
    override func viewDidLoad()
    {
        super.viewDidLoad()
        
        //As long as this keeps animating, I know I'm not blocking the main thread
        let movingBlock = UIView()
        movingBlock.backgroundColor = .blue
        view.addSubview(movingBlock)
        movingBlock.translatesAutoresizingMaskIntoConstraints = false
        conTop = movingBlock.topAnchor.constraint(equalTo: view.topAnchor)
        conTop.isActive = true
        movingBlock.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true
        movingBlock.widthAnchor.constraint(equalToConstant: 100).isActive = true
        movingBlock.heightAnchor.constraint(equalToConstant: 100).isActive = true
        
        conBot = movingBlock.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true)
        { (timer) in
            if self.conTop.isActive
            {
                self.conTop.isActive = false
                self.conBot.isActive = true
            }
            else
            {
                self.conBot.isActive = false
                self.conTop.isActive = true
            }
            DispatchQueue.main.async {
                UIView.animate(withDuration: 0.1, animations: {
                    self.view.layoutIfNeeded()
                })
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool)
    {
        super.viewDidAppear(animated)
        
        Timer.scheduledTimer(withTimeInterval: 3, repeats: true)
        { [weak self] (time) in
            let id = String.randomEmoji()
            print("Initiating nest request for \(id)")
            self?.svc.nestedRequests { (result) in
                switch result
                {
                case .success(let ints):
                    var outputStr = "nested results for \(id):\n"
                    ints.forEach({outputStr.append(String(describing: $0) + "\n")})
                    outputStr.append("end nested results")
                    print(outputStr)
                case .failure(let errStr):
                    print("ERROR: \(errStr)")
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1)
        {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true)
            { [weak self] (time) in
                let id = String.randomEmoji() + String.randomEmoji()
                print("START CHAIN \(id)")
                self?.svc.chainedRequests { (result) in
                    switch result
                    {
                    case .success(let strs):
                        var outputStr = "CHAIN RESULT FOR \(id):\n"
                        for str in strs
                        {
                            outputStr.append(str + ", ")
                        }
                        outputStr.append("end chained results")
                        print(outputStr)
                    case .failure(let errStr):
                        print("ERROR: \(errStr)")
                    }
                }
            }
        }
    }
}

enum Result<X>
{
    case success(X)
    case failure(String)
}

struct Dto: Codable
{
    let number: Int
}

class SVCAsync
{
    func nestedRequests(onDone: @escaping (Result<[Int]>) -> ())
    {
        DispatchQueue(label: "nestedReqs", qos: .userInteractive,
                      attributes: [DispatchQueue.Attributes.concurrent],
                      autoreleaseFrequency: DispatchQueue.AutoreleaseFrequency.workItem,
                      target: nil)
            .async {
                var possResult: [Int]?
                var finalErr = "Initial error"
                
                let dg = DispatchGroup()
                dg.enter()
                self.requestForOne { [weak self] (result) in
                    DispatchQueue.global(qos: .userInteractive).async {
                        switch result
                        {
                        case .success(let one):
                            possResult = [Int]()
                            possResult?.append(one)
                            
                            dg.enter()
                            self?.requestForTwo(onDone: { (secondResult) in
                                DispatchQueue.global(qos: .userInteractive).async {
                                    switch secondResult
                                    {
                                    case .success(let two):
                                        possResult?.append(two)
                                        
                                        dg.enter()
                                        self?.requestForThree(onDone: { (thirdRes) in
                                            DispatchQueue.global(qos: .userInteractive).async {
                                                switch thirdRes
                                                {
                                                case .success(let three):
                                                    possResult?.append(three)
                                                case .failure(let threeErr):
                                                    print(threeErr)
                                                    finalErr = "failure at third call"
                                                }
                                                dg.leave()
                                            }
                                        })
                                        
                                    case .failure(let twoErr):
                                        print(twoErr)
                                        finalErr = "failure at second call"
                                    }
                                    dg.leave()
                                }
                            })
                        case .failure(let oneErr):
                            print(oneErr)
                            finalErr = "failure at first call"
                        }
                        dg.leave()
                    }
                }
                dg.wait()
                
                if let finalRes = possResult
                {
                    return onDone(.success(finalRes))
                }
                else
                {
                    return onDone(.failure(finalErr))
                }
        }
    }
    
    func chainedRequests(onDone: @escaping (Result<[String]>) -> ())
    {
        let thread = DispatchQueue(label: "chainedReqs",
                                   qos: .userInteractive, attributes: [],
                                   autoreleaseFrequency: .workItem, target: nil)
        thread.async { [weak self] in
            var finalResult: [String]?
            var finalError = "Initial error"
            let dg = DispatchGroup()
            
            dg.enter()
            self?.requestForOne { (oneRes) in
                DispatchQueue.global(qos: .userInteractive).async {
                    switch oneRes
                    {
                    case .success(let one):
                        finalResult = [String]()
                        finalResult?.append(String(describing: one))
                    case .failure(let oneErr):
                        finalError = "fail at first"
                        print(oneErr)
                    }
                    dg.leave()
                }
            }
            dg.wait()
            
            if finalResult != nil
            {
                dg.enter()
                self?.requestForTwo(onDone: { (twoRes) in
                    DispatchQueue.global(qos: .userInteractive).async {
                        switch twoRes
                        {
                        case .success(let two):
                            finalResult?.append(String(describing: two))
                        case .failure(let twoErr):
                            finalError = "fail at second"
                            print(twoErr)
                        }
                        dg.leave()
                    }
                })
                dg.wait()
                dg.enter()
                self?.requestForThree(onDone: { (threeRes) in
                    DispatchQueue.global(qos: .userInteractive).async {
                        switch threeRes
                        {
                        case .success(let three):
                            finalResult?.append(String(describing: three))
                        case .failure(let threeErr):
                            print(threeErr)
                            finalError = "fail at third"
                        }
                        dg.leave()
                    }
                })
                dg.wait()
            }
            
            
            
            guard let final = finalResult else {
                return onDone(.failure(finalError))
            }
            return onDone(.success(final))
        }
    }
    
    func requestForOne(onDone: @escaping (Result<Int>) -> ())
    {
        var urlBuild = URLComponents()
        urlBuild.scheme = "http"
        urlBuild.host = "httpstat.us"
        urlBuild.path = "/200"
        urlBuild.queryItems = [URLQueryItem]()
        urlBuild.queryItems?.append(URLQueryItem(name: "sleep", value: "1000")) //Delay
        guard let url = urlBuild.url else {return onDone(.failure("invalid url"))}
        
        let req = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: req)
        { (possData, possResp, possErr) in
            if let err = possErr
            {
                return onDone(.failure(String(describing: err)))
            }
            else if let resp = possResp as? HTTPURLResponse
            {
                switch resp.statusCode
                {
                case 200:
                    return onDone(.success(1))
                default:
                    return onDone(.failure("response \(resp.statusCode)"))
                }
            }
            else
            {
                return onDone(.failure("response nil"))
            }
        }
        task.resume()
    }
    
    func requestForTwo(onDone: @escaping (Result<Int>) -> ())
    {
        var urlBuild = URLComponents()
        urlBuild.scheme = "http"
        urlBuild.host = "httpstat.us"
        urlBuild.path = "/200"
        urlBuild.queryItems = [URLQueryItem]()
        urlBuild.queryItems?.append(URLQueryItem(name: "sleep", value: "1000")) //Delay
        guard let url = urlBuild.url else {return onDone(.failure("invalid url"))}
        
        let req = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: req)
        { (possData, possResp, possErr) in
            if let err = possErr
            {
                return onDone(.failure(String(describing: err)))
            }
            else if let resp = possResp as? HTTPURLResponse
            {
                switch resp.statusCode
                {
                case 200:
                    return onDone(.success(2))
                default:
                    return onDone(.failure("response \(resp.statusCode)"))
                }
            }
            else
            {
                return onDone(.failure("response nil"))
            }
        }
        task.resume()
    }
    
    func requestForThree(onDone: @escaping (Result<Int>) -> ())
    {
        var urlBuild = URLComponents()
        urlBuild.scheme = "http"
        urlBuild.host = "httpstat.us"
        urlBuild.path = "/200"
        urlBuild.queryItems = [URLQueryItem]()
        urlBuild.queryItems?.append(URLQueryItem(name: "sleep", value: "1000")) //Delay
        guard let url = urlBuild.url else {return onDone(.failure("invalid url"))}
        
        let req = URLRequest(url: url)
        
        let task = URLSession.shared.dataTask(with: req)
        { (possData, possResp, possErr) in
            if let err = possErr
            {
                return onDone(.failure(String(describing: err)))
            }
            else if let resp = possResp as? HTTPURLResponse
            {
                switch resp.statusCode
                {
                case 200:
                    return onDone(.success(3))
                default:
                    return onDone(.failure("response \(resp.statusCode)"))
                }
            }
            else
            {
                return onDone(.failure("response nil"))
            }
        }
        task.resume()
    }
}

extension String
{
    static func randomEmoji() -> String
    {
        let emojiStart = 0x1F601
        let ascii = emojiStart + Int(arc4random_uniform(UInt32(35)))
        let emoji = UnicodeScalar(ascii)?.description
        return emoji ?? "😍"
    }
}
